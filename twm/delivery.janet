(import ./app :prefix "")

(defn- queue [state peer]
  (unless (state :delivery) (put state :delivery @{}))
  (or ((state :delivery) peer)
      (let [q @{:pending @{} :running false}]
        (put (state :delivery) peer q) q)))

(defn- ^pump [peer]
  ```
  Delivers the notices pending for `peer`, each once.

  A notice that fails is dropped, not retried. The line it went over is
  the one the peer's registration opened, and nothing opens it again
  until the peer registers again, so a retry could only fail the same
  way, later and louder. A peer that failed to hear is one that is going
  or gone; one that is not shows the past until the next notice, and the
  dropping is said either way.
  ```
  (var batch nil)
  (make-event
    {:update (fn [_ state]
               (def q (queue state peer))
               (set batch (keys (q :pending)))
               (put q :pending @{}))
     :watch
     (fn [_ state _]
       (producer
         (def client (state peer))
         (def failed
           (if (table? client)
             (seq [topic :in batch
                   :unless (first (protect (:refresh client topic)))]
               topic)
             batch))
         (if (present? failed)
           (produce (log "Projection delivery to " peer " dropped "
                         (string/join (map string failed) " ")
                         (if (table? client) ": not answered" ": no client"))))
         (produce
           (make-event
             {:update
              (fn [_ state]
                (def q (queue state peer))
                (put q :running (present? (q :pending))))
              :watch
              (fn [_ state _]
                (if ((queue state peer) :running) (^pump peer)))}
             (. "settle delivery " peer)))))}
    (. "deliver projection notices " peer)))

(defn ^invalidate
  "Queues coalesced invalidations, delivered outside the Tree manager."
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
