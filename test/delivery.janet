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

(start-suite :peer-without-client)
# Not retried, since a peer with no client may never have one, but said:
# a peer that is simply not told goes on showing the past.
(def said @"")
(def lonely @{:view @{} :log true})
(def lonely-manager (make-manager lonely))
(def err-before (dyn :err))
(setdyn :err said)
(:transact lonely-manager (delivery/^invalidate :gone :todos))
(:await lonely-manager)
(setdyn :err err-before)
(assert (string/find "Projection delivery to gone dropped todos: no client"
                     (string said))
        "notices for a peer with no client are dropped aloud")
(assert (not (get-in lonely [:delivery :gone :running]))
        "and nothing is left running for it")
(end-suite)
