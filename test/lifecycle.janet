(use spork/test)
(import ../twm/lifecycle :as life)
(import ../twm/demiurge :prefix "")
(import ../twm/thicket :prefix "")

(defn state []
  @{:view @{:spawned @{} :misses @{} :activity @{} :ran true}
    :autostart [:worker] :timeout 60})

(start-suite :generation-ownership)
(let [s (state) g (life/reserve s :worker)]
  (assert (= 1 g))
  (assert (nil? (life/reserve s :worker)) "duplicate starts coalesce")
  (life/stop s :worker)
  (life/ready s :worker g)
  (assert (= :stopping (get-in s [:view :spawned :worker])) "late ready cannot undo stop")
  (assert (nil? (life/reserve s :worker)) "replacement waits for reap")
  (life/exited s :worker g 143)
  (:transact (make-manager s) (^peer/remove :worker g))
  (def next (life/reserve s :worker))
  (assert (= 2 next))
  (:transact (make-manager s) (^peer/remove :worker g))
  (life/ready s :worker g)
  (assert (= :boot (get-in s [:view :spawned :worker])) "stale completion cannot remove successor")
  (life/ready s :worker next)
  (assert (= :mycelium (get-in s [:view :spawned :worker]))))
(end-suite)

(start-suite :real-stop-before-replace)
(let [s (state) births @[] errors @[]]
  (put s :stop-timeout 0.05)
  (put s :entries {:worker [nil nil [[] :p]]})
  (put s :nav/symbiont (fn [_] (fn [_] {})))
  (put s :spawn-process
       (fn [&]
         (array/push births true)
         (os/spawn ["janet" "-e" (if (= 1 (length births))
                                     "(ev/sleep 60)" "(os/exit 0)")]
                   :p {:in :pipe :out :pipe})))
  (def manager (make-manager s (fn [err &] (array/push errors err))))
  (:transact manager (^peer/run :worker)
             (make-watch
               (producer
                 (ev/sleep 0.05)
                 (produce (^peer/stop :worker) (^peer/run :worker))
                 (ev/sleep 0.2)
                 (put (life/record s :worker) :retry-at 0)
                 (produce CheckPeers)
                 (ev/sleep 0.2)
                 (produce Stop))))
  (:await manager)
  (assert (= 2 (length births)) "wanted successor is eventually born")
  (assert (empty? errors))
  (assert (= 2 ((life/record s :worker) :generation)))
  (assert (empty? (get-in s [:view :spawned])) "both actual children were reaped"))
(end-suite)

(start-suite :recovery-intent)
(let [s (state) g (life/reserve s :worker)]
  (life/exited s :worker g nil "spawn failed")
  (:transact (make-manager s) (^peer/remove :worker g))
  (assert (= :running ((life/record s :worker) :desired)))
  (assert (> ((life/record s :worker) :retry-at) (os/clock)))
  (assert (empty? ((CheckPeers :watch) nil s nil)) "failed start is not a hot retry loop")
  (put (life/record s :worker) :retry-at 0)
  (assert (= 1 (length ((CheckPeers :watch) nil s nil))) "all-dead system still reconciles")
  (:transact (make-manager s) StopPeers)
  (assert (empty? ((CheckPeers :watch) nil s nil)) "explicit stop withdraws recovery intent"))
(end-suite)

(start-suite :real-abnormal-exit)
(let [s (state) births @[] errors @[]]
  (put s :entries {:worker [nil nil [["janet" "-e" "(ev/sleep 0.05) (os/exit 7)"] :p]]})
  (put s :nav/symbiont (fn [_] (fn [_] {})))
  (put s :spawn-process
       (fn [cmd _]
         (array/push births true)
         (os/spawn cmd :p {:in :pipe :out :pipe})))
  (def manager (make-manager s (fn [err &] (array/push errors err))))
  (:transact manager (^peer/run :worker) (^peer/run :worker)
             (make-watch (producer (ev/sleep 0.4) (produce Stop))))
  (:await manager)
  (assert (= 1 (length births)) "only one actual child is spawned")
  (assert (empty? errors))
  (assert (= 7 ((life/record s :worker) :exit-code)) "nonzero exit is recorded, not thrown")
  (assert (empty? (get-in s [:view :spawned])) "abnormal child is reaped and released"))
(end-suite)
