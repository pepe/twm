(import ./app :prefix "" :export true)
(import ./projection :export true)

(defn- peer/reset-client
  ```
  Replaces a client after a failed open so retries start cleanly.

  Reached from the retry loops through `_`, which is `match`'s wildcard.
  It was `true`, which `match` compares literally against the tuple it is
  given and therefore never matches: the loop ended on the first failed
  open, before the client had been reset and before the tries ran out. So
  it neither connected nor said it could not, and the peer kept the
  unopened `Client` it had been given in `:update` -- a table with the
  prototype's methods and none of the remote ones, which is why the first
  call on it failed with "unknown method" long afterwards.
  ```
  [state peer]
  (when-let [old (state peer)]
    (when (table? old)
      (protect (:close old))
      (put state peer
           (make rpc/Client
                 :host (old :host)
                 :port (old :port)
                 :psk (old :psk)
                 :name (old :name)))))
  state)

(defn ^peer/renew
  ```
  Points the line held for `peer` at `address`, unless that is where it
  points already.

  A client redials by itself: `:open` lets go of whatever line it holds
  and connects again, so a peer that merely restarted needs nothing done
  to it. What `:open` cannot do is connect somewhere *else* -- it reaches
  for the `:host` and `:port` the client was built with, and those are the
  one thing a peer's new process may have changed. A registration is the
  only moment anyone says where a peer now listens, and refusing that news
  because a client already stands in the slot is how a mover is dialled at
  its old address for as long as it runs.

  So the line is disturbed only when the address is news. Registering is
  routine -- a listener renews its own every minute -- and closing a
  working connection on each of those would be churn wearing a fix's
  clothes, paid on the beat forever.

  What is left behind is the address rather than a client, which is what
  `^peer/connect` builds from and the same shape `^peer/restore` leaves on
  the way out: a slot holding a string means one thing whichever end of a
  peer's life put it there.

  The close is attempted, not required. A peer that has moved is a peer
  whose old line is likely already gone, and a close that raises must not
  keep the new address out of the slot.
  ```
  [peer address]
  (make-update
    (fn [_ state]
      (def old (state peer))
      (if (table? old)
        (unless (= address (server/address old))
          (protect (:close old))
          (put state peer address))
        (put state peer address))
      state)
    (. "renew " peer)))

(defn ^peer/connect
  "Connects to one peer"
  [peer & succ]
  (make-event
    {:update
     (fn [_ state]
       (def {:psk psk :name name} state)
       (def url (state peer))
       (when (string? url)
         (def [host port] (server/host-port url))
         (put state peer
              (make rpc/Client
                    :host host :port port
                    :psk psk :name name))))
     :watch
     (fn [_ state _]
       (producer
         (def {:name name} state)
         (var failed false)
         (var tries 0)
         (while
           # Giving up says why. A peer the thicket cannot reach is one it
           # cannot tell anything afterwards, and "cannot connect" without
           # a reason is the kind of silence that costs days.
           (match [(protect (ev/with-deadline 2 (:open (state peer)))) tries]
             [[true _] _] (produce (log name " connected to " peer))
             [[false err] 10]
             (do (set failed true)
                 (produce (log name " cannot connect to " peer ": " err)))
             _ (peer/reset-client state peer))
           (ev/sleep (* (++ tries) 0.1)))
         (if (and (not failed) (present? succ)) (produce ;succ))))}
    (. "connect peer " peer)))

(defn ^connect-peer
  "Compatibility entry point using the single peer-connection implementation."
  [peer &opt succ]
  (apply ^peer/connect peer (if (indexed? succ) succ (if succ [succ] []))))

(defn ^connect-peers
  "Connects to all the peers"
  [succ &opt fail]
  (default fail (log "Required peer connection failed"))
  (make-event
    {:update
     (fn [_ state]
       (def {:psk psk :name name :peers configured-peers} state)
       (def peers (or configured-peers (when (state :tree) [:tree])))
       (each peer peers
         (def url (state peer))
         (unless (table? url)
           (def [host port] (server/host-port url))
           (put state peer
                (make rpc/Client
                      :host host :port port
                      :psk psk :name name)))))
     :watch
     (fn [_ state _]
       (producer
         (def {:peers peers :name name} state)
         (var failed false)
         (each peer peers
           (produce (diag "connect-attempt name=" name " peer=" peer
                          " client=" (truthy? (table? (state peer)))))
           (var tries 0)
           (while
             (match [(protect (ev/with-deadline 2 (:open (state peer)))) tries]
               [[true _] _] (produce (diag "connect-ok name=" name
                                            " peer=" peer " tries=" tries)
                                         (log name " connected to " peer))
               [[false err] 10] (do
                                  (set failed true)
                                  (produce
                                    (diag "connect-fail name=" name
                                          " peer=" peer " tries=" tries
                                          " err=" err)
                                    (log name " cannot connect to " peer ": " err)))
               _ (peer/reset-client state peer))
             (ev/sleep (* (++ tries) 0.1))))
         # Several events may hang on the connecting, and what they have in
         # common is that none of them may happen before it: a door opened
         # ahead of the tree is a door that cannot answer what it accepts.
         # Spliced as `^rpc/start` splices its own, so a single event still
         # reads as one.
         (if failed
           (produce ;(if (indexed? fail) fail [fail]))
           (produce ;(if (indexed? succ) succ [succ])))))}
    "connect peers"))

(defn ^session/cap
  ```
  Saves the session capability in every view the symbiont serves.

  The capability belongs to the guardian whose entrance granted it, not to
  any one place it holds, and a symbiont standing in several of its places
  must answer for all of them from the single push that carries it.

  With `announce`, readiness is emitted from this event's watch, after
  the capability update has reached every view. A peer therefore cannot
  be treated as ready while its first request would still see no session.
  ```
  [cap &opt announce]
  (make-event
    {:update
     (fn [_ state]
       (each place [state ;(values (get state :spaces {}))]
         (if-let [view (place :view)]
           (put view :cap/session cap))))
     :watch (if announce [(projection/^ready) AetherReady])}
    "save session"))

(def register/at
  ```
  When each symbiont last registered on a peer, by peer name.

  Kept so the gap to the *next* registration in the same boot can be said
  outright. A symbiont's `^start` produces its tree registration and then,
  through `after-reg`, its registration with whatever divines for it; those
  two are ordinarily separated by 120-200us, and on the boots that went on
  to wedge they collapsed to 20us, in either order.

  That gap was legible only by accident: at 20us the two log lines were
  landing in the same `write` window and tearing, which is what made those
  boots conspicuous. Fixing the tearing (see `log`) takes the accident
  away, so the measurement is made on purpose here instead.
  ```
  @{})

(def register/window/tight
  ```
  Microseconds below which a boot's two registrations are called TIGHT.

  Drawn from five boots, not from theory: three that collapsed to ~20us
  and two that took 120us and 200us. Fifty sits between them with room on
  both sides. It is a mark to grep for, not a threshold anything acts on
  -- no code branches on this, and it should not until the link from a
  tight window to a departure that will not run is actually established.
  ```
  50)

(defn ^tree/register
  "Registers outside the manager, then installs the capability before successors."
  [peer &opt announce & after]
  (make-watch
    (fn [_ state _]
      (def name (state :name))
      (put register/at peer (os/clock))
      (producer
        # The owner says whose session the returned capability should
        # open. A tree keeping one for the whole Thicket ignores it.
        (def cap (:register (state peer) name (session/owner state)))
        (produce (^session/cap cap announce) ;(or after []))))
    (. "register " peer)))

(defn ^register
  "Registers for refresh"
  [peer]
  (make-watch
    (fn [_ state _]
      (:register (state peer) (state :name)))
    (. "register " peer)))

(def dereg/patience
  ```
  Seconds a goodbye may take before the closing goes ahead without it.

  Short on purpose. The peer being said goodbye to is on the same box over
  a loopback socket, so a goodbye that has not returned in seconds is not
  slow, it is parked.
  ```
  2)

(define-watch ClosePeers
  ```
  Says goodbye to every peer this symbiont registered with, and then closes
  the connections to them.

  Closing said nothing to anyone. A peer that registers is dialled back by
  whoever it registered with, and that provider keeps the client it dialled
  with -- so a symbiont that merely closed its own side left a live-looking
  client behind on the other. The tree then went on pushing to an address
  nobody was answering, and because `^peer/refresh` reopens a failed line
  from inside the tree's own transaction, each ghost cost it two refused
  connects with its manager blocked for both. Raise and stop the same
  symbiont a few times and the tree stops answering anything at all.

  The goodbye has to come first, which is why it lives here rather than
  beside the callers: it is said over the very connection the next line
  closes, and every path that gives up peers goes through this one. A peer
  offering no `:deregister` is skipped, and one already closed carries no
  stream to say it over -- so arriving here twice is harmless.

  The goodbye is bounded because it is a synchronous RPC run inline in this
  watch body, which puts it inside the manager's transaction, and `protect`
  catches errors but not parking. An unbounded one took production down for
  37 hours on 2026-08-14: a Leave entered here and never came back, so
  `^aether/left` was never written, `Exit` was never reached, the door was
  never handed back, and every visitor got a bare 401 until the box was
  restarted. A deadline turns the park into an error `protect` already
  knows what to do with, and keeps the ordering the caller depends on. A
  peer that misses its goodbye is left holding a ghost client, which is the
  survivable fault described above; the thicket stopping is not.
  ```
  [_ state _]
  (def {:peers peers :name name} state)
  (def unsaid @[])
  (each peer peers
    (def client (state peer))
    (when (table? client)
      (when-let [_ (client :stream)
                 dereg (client :deregister)]
        (unless (first (protect (ev/with-deadline dereg/patience
                                  (dereg client name))))
          (array/push unsaid peer)))
      # Bounded for the same reason as the goodbye above. `protect`
      # catches errors but not parking, and a close that parks holds
      # the whole departure behind it -- the Aether, the handing back
      # of the door, and every peer after this one in the loop.
      (protect (ev/with-deadline dereg/patience (:close client)))))
  # Said after the closing rather than beside each failure: the whole point
  # is that this body must reach its end, and a log event is produced, not
  # written, so it cannot itself be what stops.
  (tuple ;(seq [peer :in unsaid]
            (log name "'s goodbye to " peer " did not return in "
                 dereg/patience "s; closed anyway"))))

(defn close-peers-stop
  "RPC function that closes peers and stops the server"
  [&]
  (produce ClosePeers
           (log "RPC server going down")
           Stop)
  :ok)

(defn ^tree/refresh-view
  "Requests an asynchronous Tree snapshot for the Thicket's living spaces."
  [& colls]
  (projection/^refresh colls))

(defn fixtures
  "Combine members of the `sets` to get `n` uniq combinations"
  [n & sets]
  (def rng (math/rng (os/cryptorand 8)))
  (def res @{})
  (while (< (length res) n)
    (put res
         (freeze
           (seq [set :in sets :let [ls (length set)]]
             (get set (math/rng-int rng ls))))
         true))
  (keys res))

(defn =>guardian/spaces
  ```
  Navigation to the living spaces `guardian` inhabits, as the sorted
  array of symbionts that named it their `:guarded-by`.

  Guarding is declared once, by the symbiont whose place is taken. Read
  from this side it stays derivable rather than restated, so a guardian
  can never disagree with a symbiont about who stands in its stead.
  ```
  [guardian]
  (=> :symbionts
      |(sorted (seq [[symbiont conf] :pairs $
                     :when (= guardian (get conf :guarded-by))]
                 symbiont))))

(defn =>mycelium/node
  ```
  Navigation to symbiont mycelium.

  Every symbiont that answers on an address declares it, guardians no
  less than the rest. A guardian used to own no node and silently answer
  on the address of what it guarded, which held only while the two were
  never alive at once. One that outlives its handover needs an address
  of its own, and one that has none should say so by failing to start
  rather than by quietly becoming a second symbiont at another door.
  ```
  [symbiont]
  (=> :mycelium :nodes symbiont))

(defn =>mycelium/peers
  "Navigation to `symbiont` peers"
  [=>mycelium]
  (let [c @[]
        =>peers (=> =>mycelium :peers)]
    (>if (=> =>peers present?)
         (=> (<- c (=> =>peers))
             |(tabseq [i :in (array/pop c)]
                i ((=> (=>mycelium/node i) :rpc) $)))
         (>base {}))))
