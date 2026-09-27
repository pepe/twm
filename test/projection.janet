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
         :tree @{:stream true :snapshot (fn [_ colls owner]
                            (array/push calls [colls owner])
                            (ev/sleep 0.05)
                            {:epoch "a" :revision 1
                             :values (tabseq [coll :in colls] coll true)})}})
(def manager (make-manager s))
(:transact manager ;(seq [_ :range [0 20]] (projection/^refresh [:focused])))
(assert (not (get-in s [:view :focused])) "state manager returns before the network does")
(:await manager)
(assert (= 1 (length calls)) "a queued burst coalesces into one snapshot")
(assert (= :projection (get-in calls [0 1]))
        "a snapshot names whose session it asks for")
(assert (get-in s [:view :focused]))
(assert (not (s :projection/running)))
(put (s :tree) :snapshot (fn [&] (error "offline")))
(:transact manager (projection/^refresh [:focused]))
(:await manager)
(assert (= "offline" (get-in s [:view :projection/error])))
(assert (not (s :projection/running)) "failure releases the in-flight slot")
(end-suite)

(start-suite :session-owner)
(assert (= :door (session/owner @{:name :door :guards :place}))
        "a guardian owns the sessions its entrance grants")
(assert (= :door (session/owner @{:name :place :guarded-by :door}))
        "a guarded symbiont's session is its guardian's")
(assert (= :student (session/owner @{:name :student}))
        "anything else names only itself")
(def guarded-calls @[])
(def g @{:name :place :guarded-by :door :view @{:notify @{}}
         :tree @{:stream true :snapshot (fn [_ colls owner]
                            (array/push guarded-calls owner)
                            {:epoch "a" :revision 1
                             :values (tabseq [coll :in colls] coll true)})}})
(def guarded-manager (make-manager g))
(:transact guarded-manager (projection/^refresh [:cap/session]))
(:await guarded-manager)
(assert (deep= @[:door] guarded-calls)
        "a guarded symbiont asks for its guardian's session")
(end-suite)

(start-suite :stalled-projection)
# A fetch that never reports back holds the in-flight slot for good, and
# every later refresh only joins the queue behind it. The view then goes
# on showing the past with nothing in the log, which is how a Dashboard
# on staging came to offer a todo the Tree had finished minutes before.
(def said @"")
(def stalled @{:name :projection :log true :view @{:notify @{}}
               :projection/running true
               :projection/since (- (os/clock :monotonic) 60)
               :tree @{:stream true :snapshot (fn [&] (error "not asked"))}})
(def stalled-manager (make-manager stalled))
(def err-before (dyn :err))
(setdyn :err said)
(:transact stalled-manager
           (projection/^refresh [:focused]) (projection/^refresh [:todos]))
(setdyn :err err-before)
(assert (= 1 (length (string/find-all "for a snapshot; refreshes are queuing"
                                      (string said))))
        "a snapshot long out is said to stall the refreshes behind it, once")
(assert (stalled :projection/running) "and saying so starts no second fetch")
(end-suite)
