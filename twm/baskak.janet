# A Baskak keeps consequence-relative sufficiency: given a request for a
# consequence, it asks whether the grounds for it are there, and if they
# are it says so in a Yarlyk. It authenticates nobody and authorizes
# nothing. The grounds are its Thicket's to supply -- a live session in the
# Tree, here -- and the authority stays with the door the warrant is shown
# at, which may refuse it all the same.
(import ./thicket :prefix "")
(import ./yarlyk :prefix "")

(defn baskak/grant-for
  ```
  The grant in `grants` that lets `avatar` request `capability` at `door`,
  or nil.

  A grant names its capability as a flag, exactly as a symbiont names its
  role, and only a flag set to `true` counts. So a viewer's grant can
  never be stretched to warrant `:admin`: a Yarlyk must not justify a
  stronger consequence than the one it was issued for.
  ```
  [grants avatar door capability]
  (find |(and (= avatar ($ :avatar))
              (= door ($ :door))
              (keyword? capability)
              (true? (get $ capability)))
        grants))

(defn baskak/grants
  "The doors `avatar` holds a grant for, each as `{:door :capability}`."
  [grants avatar]
  (seq [grant :in grants
        :when (= avatar (grant :avatar))
        [k v] :pairs grant
        :when (true? v)]
    {:door (grant :door) :capability k}))

(defn baskak/warrant
  ```
  Answers `request` with a Yarlyk, or `[:refused reason]`.

  `request` asks for one capability at one door on behalf of one avatar,
  and offers the avatar's session as its ground. `baskak` is this Baskak's
  own configuration -- its grants, its signing key, the validity it gives
  and the name it signs as -- and `grounds?` is how its Thicket says
  whether the session offered is live for that avatar.

  The grant is checked before the grounds, so a request for a door the
  avatar was never granted costs no call to the Tree. Neither check is
  skipped: a grant without a live session is someone else asking in the
  avatar's name, and a live session without a grant is asking for more
  than was given.
  ```
  [baskak request grounds? &opt now]
  (default now (os/time))
  (def {:avatar avatar :session session :door door :capability capability}
    (if (dictionary? request) request {}))
  (def {:grants grants :sign-key sign-key :yarlyk/ttl ttl
        :thicket thicket :name name} baskak)
  (cond
    (not (and (keyword? avatar) (present-string? door)
              (keyword? capability)))
    [:refused :malformed]
    (not (baskak/grant-for grants avatar door capability)) [:refused :grant]
    (not (and (present-string? session) (grounds? avatar session)))
    [:refused :grounds]
    (yarlyk/issue {:issuer (string thicket "/" name)
                   :avatar (string thicket "/" avatar)
                   :claim :avatar/authenticated
                   :grounds {:session :live :checked now}
                   :burden :admission/v1
                   :capability capability
                   :consequence :session/open
                   :door door}
                  sign-key ttl now)))

(defn baskak/rpc-funcs
  ```
  RPC functions of a Baskak: `:grants` and `:warrant`.

  The log says who asked for which door and what came of it, and never
  the session offered nor the signature given.
  ```
  [baskak grounds?]
  @{:grants
    (fn grants [_ avatar] (baskak/grants (baskak :grants) avatar))
    :warrant
    (fn warrant [_ request]
      (def answer (baskak/warrant baskak request grounds?))
      (def {:avatar avatar :door door :capability capability}
        (if (dictionary? request) request {}))
      (produce (log "baskak warrant avatar=" avatar " door=" door
                    " capability=" capability " outcome="
                    (if (dictionary? answer) "issued" (answer 1))))
      answer)})
