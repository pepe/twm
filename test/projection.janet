(use spork/test)
(import ../twm/projection)
(import ../twm/app :prefix "")

(start-suite :atomic-projection)
(def view @{:notify @{} :focused false})
(projection/install view {:epoch "a" :revision 2 :values {:focused :new}})
(projection/install view {:epoch "a" :revision 1 :values {:focused :old :tracking true}})
(assert (= :new (view :focused)) "late data cannot undo a newer field")
(assert (view :tracking) "an older snapshot may supply an unseen field")
(assert-error "preparation failure is atomic"
  (projection/install view {:epoch "a" :revision 3 :values {:focused :bad}}
                      (fn [&] (error "prepare failed"))))
(assert (= :new (view :focused)))
(end-suite)

(start-suite :asynchronous-coalescing)
(def calls @[])
(def s @{:name :projection :view @{:notify @{} :focused false}
         :tree @{:stream true :snapshot (fn [_ colls]
                            (array/push calls colls)
                            (ev/sleep 0.05)
                            {:epoch "a" :revision 1
                             :values (tabseq [coll :in colls] coll true)})}})
(def manager (make-manager s))
(:transact manager ;(seq [_ :range [0 20]] (projection/^refresh [:focused])))
(assert (not (get-in s [:view :focused])) "state manager returns before the network does")
(:await manager)
(assert (= 1 (length calls)) "a queued burst coalesces into one snapshot")
(assert (get-in s [:view :focused]))
(assert (not (s :projection/running)))
(put (s :tree) :snapshot (fn [&] (error "offline")))
(:transact manager (projection/^refresh [:focused]))
(:await manager)
(assert (= "offline" (get-in s [:view :projection/error])))
(assert (not (s :projection/running)) "failure releases the in-flight slot")
(end-suite)
