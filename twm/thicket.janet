(import ./app :prefix "" :export true)

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
           (match [(protect (:open (state peer))) tries]
             [[true _] _] (produce (log name " connected to " peer))
             [[false err] 10]
             (produce (log name " cannot connect to " peer ": " err))
             _ (peer/reset-client state peer))
           (ev/sleep (* (++ tries) 0.1)))
         (if (present? succ) (produce ;succ))))}
    (. "connect peer " peer)))

(defn ^connect-peer
  "Connects to one peer"
  [peer &opt succ]
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
           (match [(protect (:open (state peer))) tries]
             [[true _] _] (produce (log name " connected to " peer))
             [[false err] 10]
             (produce (log name " cannot connect to " peer ": " err))
             _ (peer/reset-client state peer))
           (ev/sleep (* (++ tries) 0.1)))
         (if succ (produce ;succ))))}
    (. "connect peer " peer)))

(defn ^connect-peers
  "Connects to all the peers"
  [succ &opt fail]
  (default fail succ)
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
             (match [(protect (:open (state peer))) tries]
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

  The capability is the tenant's, not any one place's, and a symbiont
  standing in several of a tenant's places must answer for all of them
  from the single push that carries it.

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
     :watch (if announce AetherReady)}
    "save session"))

(defn ^tenant/register
  ```
  Registers for whatever `peer` pushes on behalf of `tenant`.

  A symbiont registers under its own name, never under the name of a place
  it happens to be standing in. A guardian hands such a place over the
  moment the symbiont it guards rises, and a registration pointing there
  would be answered by the risen symbiont from then on -- the guardian
  would keep serving on a capability nobody could tell it had expired.

  `announce` asks the saved capability to report readiness only after its
  update; it is used for a symbiont's first registration.
  ```
  [peer &opt tenant announce]
  (make-watch
    (fn [_ state _]
      (def {:name name} state)
      (default tenant ((>or (=<> :guards) (=<> :name)) state))
      [(diag "register name=" name " tenant=" tenant " peer=" peer
             " target-present=" (truthy? (state peer)))
       (log tenant " registers on " peer)
       (^session/cap (:register (state peer) name tenant) announce)])
    (. "register " peer)))

(defn ^register
  "Registers for refresh"
  [peer]
  (make-watch
    (fn [_ state _]
      (:register (state peer) (state :name)))
    (. "register " peer)))

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
  ```
  [_ state _]
  (def {:peers peers :name name} state)
  (def tenant ((>or (=<> :guards) (=<> :name)) state))
  (each peer peers
    (def client (state peer))
    (when (table? client)
      (when-let [_ (client :stream)
                 dereg (client :deregister)]
        (protect (dereg client name tenant)))
      (protect (:close client)))))

(defn close-peers-stop
  "RPC function that closes peers and stops the server"
  [&]
  (produce ClosePeers
           (log "RPC server going down")
           Stop)
  :ok)

(defn ^tenant/refresh-view
  "Refreshes the data in view from tree for the tenant"
  [& colls]
  (make-update
    (fn [_ state]
      (def {:tree tree :tenant tenant :name name} state)
      # Tree's tenant RPC schema is keyword-only. Older or hand-built
      # configurations may carry a string, and guardians may have no
      # explicit tenant while they are being assembled.
      (def raw-tenant (or tenant name))
      (def rpc-tenant (if (and raw-tenant (not (keyword? raw-tenant)))
                        (keyword raw-tenant)
                        raw-tenant))
      (when rpc-tenant
        (each place [state ;(values (get state :spaces {}))]
          (if-let [view (place :view)]
            (each coll colls
              (put view coll (coll tree rpc-tenant)))))))
    (. "refresh view " ;colls)))

(defn ^peer/refresh-view
  "Refreshes the data in view from tree for the peer"
  [& colls]
  (make-update
    (fn [_ state]
      (def {:tree tree :view view :name name} state)
      (each coll colls
        (put view coll (coll tree name))))
    (. "refresh view " ;colls)))

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
