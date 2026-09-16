(import ./app :prefix "")

(defn- queue [state peer]
  (unless (state :delivery) (put state :delivery @{}))
  (or ((state :delivery) peer)
      (let [q @{:pending @{} :running false :failures 0}]
        (put (state :delivery) peer q) q)))

(defn- ^pump [peer]
  (var batch nil)
  (make-event
    {:update (fn [_ state]
               (def q (queue state peer))
               (set batch (keys (q :pending)))
               (put q :pending @{}))
     :watch
     (fn [_ state _]
       (producer
         (def failed @[])
         (def client (state peer))
         (when (table? client)
           (each topic batch
             (def [ok _]
               (protect (ev/with-deadline 3
                          (unless (client :stream) (:open client))
                          (:refresh client topic))))
             (unless ok (array/push failed topic))))
         (produce
           (make-event
             {:update
              (fn [_ state]
                (def q (queue state peer))
                (each topic failed (put (q :pending) topic true))
                (put q :failures (if (empty? failed) 0 (inc (q :failures))))
                (put q :running (present? (q :pending))))
              :watch
              (fn [_ state _]
                (def q (queue state peer))
                (when (q :running)
                  (make-watch
                    (producer
                      (when (pos? (q :failures))
                        (produce (log "Projection delivery to " peer " will retry"))
                        (ev/sleep (min 30 (math/pow 2 (min 5 (q :failures))))))
                      (produce (^pump peer))))))}
             (. "settle delivery " peer)))))}
    (. "deliver projection notices " peer)))

(defn ^invalidate
  "Queues bounded, coalesced invalidations; retries never occupy the Tree manager."
  [peer & topics]
  (var start false)
  (make-event
    {:update
     (fn [_ state]
       (def q (queue state peer))
       (each topic topics (put (q :pending) topic true))
       (unless (q :running) (put q :running true) (set start true)))
     :watch (fn [&] (when start (^pump peer)))}
    (. "invalidate " peer)))
