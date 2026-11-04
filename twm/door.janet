# A door is a guardian's second way in. Its entrance asks a person for a
# secret; its door asks an Avatar from another Thicket for a Yarlyk, over
# an RPC listener of its own with the key of that one relation. The
# warrant says the grounds were sufficient elsewhere. Whether that is
# enough here is the door's to decide, by its own list of who it admits:
# a Thicket stays sovereign over its own places.
(import ./thicket :prefix "")
(import ./yarlyk :prefix "")

(def door/consequence "The one consequence a door grants." :session/open)

(def door/yarlyk-max
  "The longest validity a door accepts, unless it says otherwise."
  120)

(defn door/id
  "The id a Yarlyk must name to be shown at this guardian's door: `<thicket>/<guardian>`."
  [state]
  (string (state :thicket) "/" (state :name)))

(defn door/admits
  ```
  The entry of `admits` letting `avatar` in with `capability`, or nil.

  Like a grant, an admit names its capability as a flag, and only `true`
  counts. Being named is not enough: an avatar admitted as a viewer is
  not let in as an admin because its warrant asks for it.
  ```
  [admits avatar capability]
  (find |(and (= avatar ($ :avatar))
              (keyword? capability)
              (true? (get $ capability)))
        admits))

(defn door/token
  ```
  A fresh session for one admission: 32 random bytes in hex.

  Random rather than derived from the guardian's key and the second, as a
  sign-in's is, because a door may admit two Avatars within one second
  and each must hold a session of its own.
  ```
  []
  (string/join (map |(string/format "%02x" $) (random/buf 32))))

(defn door/place
  ```
  The place a guardian with a door admits into.

  A guardian of one place opens that one. A guardian of several has to
  say which with `:door/place`, the symbiont an Avatar lands on; picking
  one would be guessing. Its places must all open with the sessions of
  one owner, or the session a door grants would open the landing place
  and leave the others shut, so a guardian whose places differ raises
  here, as one keeping identities does.
  ```
  [state]
  (def spaces (get state :spaces {}))
  (def named (state :door/place))
  (assert (nil? (state :identities))
          (string "Guardian " (state :name) " cannot keep both identities and a door."))
  (assert (or named (= 1 (length spaces)))
          (string "Guardian " (state :name) " with a door guards " (length spaces)
                  " places; name the one an Avatar lands on as :door/place."))
  (def place (if named (get spaces named) (first (values spaces))))
  (assert place
          (string "Guardian " (state :name) " has no place " named " to land on."))
  (def owner (place/owner state place))
  (each other (values spaces)
    (assert (= owner (place/owner state other))
            (string "Guardian " (state :name) " guards places of different owners; "
                    "one door cannot open them all.")))
  place)

(defn door/held?
  "Whether the guardian is answering on `place`'s HTTP address itself."
  [place]
  (truthy? (get-in (space/held place) [:http :listener])))

(defn door/admit
  ```
  Admits the Avatar a Yarlyk speaks for, or says why not.

  In order: the warrant must be genuine, current, unused and meant for
  this door (`yarlyk/verify`); then this door must admit that avatar with
  that capability. Only then is a session made. It is published as one
  more live session of the place's owner, held by the avatar, so nobody
  else's is ended; and if the guardian is still holding the place, the
  place is handed to the symbiont it guards, exactly as after a sign-in.

  `door` carries what persists between calls: the trusted issuers, the
  door's id, when it started and the serials it has seen. `ops` does what
  belongs to the guardian: `:publish` a session as `session/publish`
  does, and `:handover` a place.

  Returns `{:token :address}` -- the session, to be presented as a bearer,
  and the address it opens -- or `[:refused reason]`.
  ```
  [state door place ops &opt now]
  (fn admit [wire]
    (match (yarlyk/verify wire door now)
      [:refused reason] [:refused reason]
      [:ok claims]
      (let [{:avatar avatar :capability capability} claims]
        (cond
          (not (find |(= avatar ($ :avatar)) (state :door/admits)))
          [:refused :not-admitted]
          (not (door/admits (state :door/admits) avatar capability))
          [:refused :capability]
          (let [token (door/token)]
            ((ops :publish) token (place/owner state place) {:holder avatar})
            (when (door/held? place) ((ops :handover) place))
            {:token token :address (place :address)}))))))

(defn door/functions
  ```
  The RPC functions of a guardian's door: `:entry/admit`, `:entry/end`
  and `:ping`.

  `:entry/end avatar` ends every session the avatar holds at this place,
  and nobody else's; `:entry/end avatar token` ends that one session, if
  the avatar holds it -- an Avatar leaving one door in one tab leaves its
  other tabs where they are. The log names the avatar and the outcome,
  never a warrant, a signature or a session.
  ```
  [state ops]
  (def place (door/place state))
  (def door @{:issuers (state :door/issuers)
              :door (door/id state)
              :consequence door/consequence
              :max-ttl (get state :door/yarlyk-max door/yarlyk-max)
              :started (os/time)
              :seen @{}})
  (def admit (door/admit state door place ops))
  @{:entry/admit
    (fn entry/admit [_ wire]
      (def answer (admit wire))
      (produce (log (state :name) " door admit outcome="
                    (if (dictionary? answer) "admitted" (answer 1))))
      answer)
    :entry/end
    (fn entry/end [_ avatar &opt token]
      (cond
        (not (find |(= avatar ($ :avatar)) (state :door/admits)))
        [:refused :unknown-avatar]
        (and token (not (present-string? token)))
        [:refused :malformed]
        (do
          ((ops :publish) "" (place/owner state place)
                          (if token {:holder avatar :token token} {:holder avatar}))
          (produce (log (state :name) " door ended "
                        (if token "a session" "the sessions") " of " avatar))
          :ok)))
    :ping (fn ping [&] :pong)})

(defn ^door/open
  ```
  Opens the door of a guardian whose configuration gives it one, on its
  own membrane address with that relation's key; does nothing otherwise.

  Opened after the peers are connected, for the reason the HTTP doors
  are: a door that admits before the tree is reachable admits into
  nothing. The time it opens is remembered, and a Yarlyk issued before it
  is refused -- the serials seen before a restart are gone with it.
  ```
  [ops]
  (make-watch
    (fn [_ state _]
      (when (state :door/issuers)
        (assert (present-string? (state :membrane/rpc))
                (string "Guardian " (state :name) " has a door but no membrane :rpc."))
        (assert (present-string? (state :membrane/key))
                (string "Guardian " (state :name) " has a door but no membrane :key."))
        (^rpc (state :membrane/rpc) (door/functions state ops)
              (state :membrane/key) (. (state :name) " door") (state :debug))))
    "door"))
