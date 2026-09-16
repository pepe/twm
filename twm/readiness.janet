# This gate describes readiness, not authentication. A failed gate never admits
# a request, and a cancelled waiter never stays in its producer's bookkeeping.
(def- gates @{})

(defn- gate [view]
  (or (gates view)
      (let [g @{:status :pending :waiters @{}
                :generation (string/join (map |(string/format "%02x" $)
                                              (os/cryptorand 12)))}]
        (put gates view g) g)))

(defn status
  "Returns a small public readiness description, without session information."
  [view]
  (def g (gate view))
  {:ready (= :ready (g :status)) :status (g :status)
   :generation (g :generation) :role (if (view :guards) "guardian" "symbiont")})

(defn settle
  "Completes a readiness gate and wakes all waiters, without waiting for them."
  [view state &opt reason]
  (assert (index-of state [:ready :failed :cancelled]) "Invalid readiness outcome")
  (def g (gate view))
  (put g :status state)
  (put g :reason reason)
  (each waiter (keys (g :waiters))
    (ev/give waiter [state reason]))
  (table/clear (g :waiters)))

(defn await
  "Waits for a ready gate, raises on failure/deadline, and always removes its waiter."
  [view &opt seconds cancelled]
  (default seconds 10)
  (def g (gate view))
  (def waiter (ev/chan 1))
  (defer (put (g :waiters) waiter nil)
    (def [state reason]
      (if (= :pending (g :status))
        (do (put (g :waiters) waiter true)
            (ev/with-deadline seconds
              (if cancelled (last (ev/select waiter cancelled)) (ev/take waiter))))
        [(g :status) (g :reason)]))
    (unless (= :ready state)
      (error (if (= reason :client-disconnected) reason
               (string "Projection " state ": " reason))))
    true))
