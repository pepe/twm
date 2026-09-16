(use spork/test)
(import ../twm/operation)
(import ../twm/app :prefix "")
(import ../twm/demiurge)

(start-suite :maintenance-receipts)
(def state @{:view @{} :value 0})
(def manager (make-manager state (fn [&])))
(def result @[])
(:transact manager
  (make-watch
    (producer
      (def accepted
        (operation/submit :test
          (fn [state record]
            (ev/sleep 0.02)
            (operation/step record :writing
              [(make-effect (fn [&] (error "disk full")))
               (make-update (fn [_ s] (put s :value 1)))]))))
      (array/push result accepted)
      (array/push result (protect (operation/submit :overlap (fn [&])))))))
(:await manager)
(def receipt (operation/status (state :view) (get-in result [0 :id])))
(assert (= :accepted (get-in result [0 :status])))
(assert (= false (get-in result [1 0])) "maintenance admission is serialized")
(assert (= :failed (receipt :status)))
(assert (= :writing (receipt :phase)))
(assert (= 0 (state :value)) "failure prevents the next release step")
(assert (nil? (get-in state [:view :operation])) "failure releases maintenance admission")
(:transact manager
  (make-watch (producer
    (operation/submit :test
      (fn [state record]
        (operation/step record :writing [(make-update (fn [_ s] (put s :value 2)))]))))))
(:await manager)
(assert (= 2 (state :value)))
(assert (some |(= :completed ($ :status)) (values (get-in state [:view :operations]))))
(assert (nil? (operation/status (state :view) "unknown")))
(end-suite)

(start-suite :failed-flush-stays-dirty)
(put state :dirty true)
(put state :store @{:flush (fn [&] (error "cannot persist"))})
(:transact manager Flush)
(assert (state :dirty))
(put state :store @{:flush (fn [&] true)})
(:transact manager Flush)
(assert (not (state :dirty)))
(end-suite)

(start-suite :failed-install-keeps-active-peer)
(def unchanged @{:build-path "." :builds [:absent-test-peer]
                 :view @{:spawned @{:absent-test-peer :mycelium}
                         :lifetimes @{:absent-test-peer @{:generation 7 :desired :running}}}})
(def release-manager (make-manager unchanged (fn [&])))
(:transact release-manager
  (make-watch (producer
    (operation/submit :peer/release
      |(demiurge/peer/maintain $0 $1 :peer/release :absent-test-peer)))))
(:await release-manager)
(assert (= :mycelium (get-in unchanged [:view :spawned :absent-test-peer])))
(assert (= 7 (get-in unchanged [:view :lifetimes :absent-test-peer :generation])))
(assert (= :failed (get (first (values (get-in unchanged [:view :operations]))) :status)))
(end-suite)

(start-suite :unknown-outcome-keeps-admission-closed)
(:transact manager
  (make-watch (producer (operation/submit :ambiguous
    (fn [&] (error {:status :unknown :failure "lost completion"}))))))
(:await manager)
(assert (get-in state [:view :operation]))
(assert (= :unknown (get (operation/status (state :view) (get-in state [:view :operation])) :status)))
(end-suite)
