(import ./app :prefix "" :export true)

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
           (match [(protect (:open (state peer))) tries]
             [[true _] _] (produce (log name " connected to " peer))
             [[false _] 10] (produce (log name " cannot connect to " peer "."))
             true)
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
             [[false _] 10] (produce (log name " cannot connect to " peer "."))
             true)
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
       (def {:psk psk :name name :peers peers} state)
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
           (var tries 0)
           (while
             (match [(protect (:open (state peer))) tries]
               [[true _] _] (produce (log name " connected to " peer))
               [[false _] 10] (do
                                (set failed true)
                                (produce (log name " cannot connect to " peer ".")))
               true)
             (ev/sleep (* (++ tries) 0.1))))
         (if failed (produce fail) (produce succ))))}
    "connect peers"))

(defn ^session/cap
  ```
  Saves the session capability in every view the symbiont serves.

  The capability is the tenant's, not any one place's, and a symbiont
  standing in several of a tenant's places must answer for all of them
  from the single push that carries it.
  ```
  [cap]
  (make-update
    (fn [_ state]
      (each place [state ;(values (get state :spaces {}))]
        (if-let [view (place :view)]
          (put view :cap/session cap))))
    "save session"))

(defn ^tenant/register
  "Registers for refresh"
  [peer &opt tenant]
  (make-watch
    (fn [_ state _]
      (def name ((>or (=<> :guards) (=<> :name)) state))
      (default tenant name)
      [(log tenant " registers on " peer)
       (^session/cap (:register (state peer) name tenant))])
    (. "register " peer)))

(defn ^register
  "Registers for refresh"
  [peer]
  (make-watch
    (fn [_ state _]
      (:register (state peer) (state :name)))
    (. "register " peer)))

(define-watch ClosePeers
  "Closes all connections to peers"
  [_ state _]
  (def {:peers peers} state)
  (each peer peers (protect (:close (state peer)))))

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
      (def {:tree tree :tenant tenant} state)
      (each place [state ;(values (get state :spaces {}))]
        (if-let [view (place :view)]
          (each coll colls
            (put view coll (coll tree tenant))))))
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

(defn =>guardian/space
  ```
  Navigation to the single living space `guardian` inhabits, or nil.

  A symbiont still raises one HTTP and one mycelium server, so it can
  stand in one place at a time. When those become many, this becomes
  `=>guardian/spaces` and the assert below is what falls away.
  ```
  [guardian]
  (=> (=>guardian/spaces guardian)
      |(do
         (assert (>= 1 (length $))
                 (string "Guardian " guardian " would inhabit " (length $)
                         " living spaces, and can hold one."))
         (first $))))

(defn =>mycelium/node
  ```
  Navigation to symbiont mycelium.

  A guardian owns no node. It answers on the address of the symbiont it
  guards and takes only that: whom it speaks to is its own business,
  declared on itself, because guarding is inhabiting a surface rather
  than inheriting every relation behind it.
  ```
  [symbiont]
  (def c @[])
  (>or (=> :mycelium :nodes symbiont)
       (>when (=>guardian/space symbiont)
              (=> (<- c (=>guardian/space symbiont))
                  (=> :mycelium :nodes |(get $ (array/pop c))
                      |(if $ {:rpc (get $ :rpc)}))))))

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
