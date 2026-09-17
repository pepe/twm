(use spork/test)
(import ../twm/thicket :prefix "")

(start-suite :announced-capability-readiness)
(let [own @{} one @{} two @{}
      state @{:name :guardian :view own
              :spaces {:one {:view one} :two {:view two}}}
      manager (make-manager state)
      cap (fn [&] true)]
  (:transact manager (^session/cap cap))
  (each view [own one two]
    (assert (not (get (readiness/status view) :ready))
            "capability alone does not finish a full projection"))
  (:transact manager (^session/cap cap true))
  (:await manager)
  (each view [own one two]
    (assert (get (readiness/status view) :ready)
            "announced guardian readiness reaches every inhabited space")
    (assert (= cap (view :cap/session)))))
(end-suite)

# Giving up a peer is two things, and the order is the whole of it: the
# goodbye is said over the very connection the close then takes away. What
# went wrong before was not that the goodbye was said badly but that it was
# never said at all, and nothing on this side could tell -- the cost landed
# on the tree, minutes later, as a push into a process that had gone.

(defn stub/client
  "A peer client that records what was asked of it, in order."
  [record &named deregister stream]
  (default stream :open)
  (def client @{:stream stream})
  (when (not= deregister false)
    (put client :deregister
         (fn [self & args] (array/push record [:deregister ;args]) :ok)))
  (put client :close
       (fn [self] (put self :stream nil) (array/push record [:close]) self))
  client)

(start-suite :closing-peers)

# The ordinary case: say goodbye, then close.
(let [record @[]
      state @{:name :pepe :peers [:tree] :tree (stub/client record)}]
  (:transact (make-manager state) ClosePeers)
  (assert (deep= record @[[:deregister :pepe :pepe] [:close]])
          "a peer is deregistered before its connection is closed"))

# A guardian registers for the tenant whose place it stands in, not under
# its own name, so it must say goodbye under that same tenant.
(let [record @[]
      state @{:name :pepe/sentry :guards :pepe :peers [:tree]
              :tree (stub/client record)}]
  (:transact (make-manager state) ClosePeers)
  (assert (deep= record @[[:deregister :pepe/sentry :pepe] [:close]])
          "a guardian deregisters under the tenant it guards"))

# Not every peer keeps registrations; one that offers no `:deregister` is
# still closed.
(let [record @[]
      state @{:name :pepe :peers [:augur]
              :augur (stub/client record :deregister false)}]
  (:transact (make-manager state) ClosePeers)
  (assert (deep= record @[[:close]])
          "a peer with nothing to deregister from is only closed"))

# Arriving here twice must not speak over a connection that is gone: the
# guarded stop path closes peers and then stands down, which closes again.
(let [record @[]
      client (stub/client record)
      state @{:name :pepe :peers [:tree] :tree client}
      manager (make-manager state)]
  (:transact manager ClosePeers)
  (:transact manager ClosePeers)
  (assert (deep= record @[[:deregister :pepe :pepe] [:close] [:close]])
          "a closed peer is not deregistered a second time"))

# Every peer gets its turn, not merely the first.
(let [record @[]
      state @{:name :pepe :peers [:tree :augur]
              :tree (stub/client record)
              :augur (stub/client record)}]
  (:transact (make-manager state) ClosePeers)
  (assert (= 2 (length (filter |(= :deregister ($ 0)) record)))
          "every registered peer is told"))

# A peer that has not been connected is a URL, not a client, and there is
# nobody to say anything to.
(let [state @{:name :pepe :peers [:tree] :tree "localhost:4444"}]
  (assert (= :ok (do (:transact (make-manager state) ClosePeers) :ok))
          "an unconnected peer is passed over without error"))

(end-suite)
