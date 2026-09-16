(use spork/test)
(import ../twm/delivery)
(import ../twm/app :prefix "")

(start-suite :tree-does-not-wait-for-listeners)
(def calls @[])
(def state @{:view @{} :changed false
             :listener @{:stream true :refresh (fn [_ topic]
                                               (ev/sleep 0.03)
                                               (array/push calls topic)
                                               :ok)}})
(def manager (make-manager state))
(:transact manager
  ;(seq [_ :range [0 1000]] (delivery/^invalidate :listener :todos :tracking))
  (make-update (fn [_ s] (put s :changed true))))
(assert (state :changed) "canonical state still advances before any listener answers")
(assert (empty? calls))
(:await manager)
(assert (= 2 (length calls)) "a thousand invalidations become one delivery per topic")
(assert (not (get-in state [:delivery :listener :running])))
(assert (empty? (get-in state [:delivery :listener :pending])))
(end-suite)
