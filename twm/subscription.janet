# Live transport bookkeeping stays outside the serializable application view.
(def- registrations @{})

(defn open
  "Registers a durable subscriber before its first local snapshot is read."
  [view topics &opt control]
  (def sub @{:wake (ev/chan 1) :closed-signal (ev/chan 1)
             :pending @{} :control-topic control :view view
             :topics topics :closed false :notified false})
  (unless (registrations view) (put registrations view @{}))
  (put (registrations view) sub true)
  sub)

(defn close
  "Removes a subscriber and wakes any outstanding read; safe to call repeatedly."
  [sub]
  (unless (sub :closed)
    (put sub :closed true)
    (ev/give (sub :closed-signal) [:cancelled :client-disconnected])
    (def held (registrations (sub :view)))
    (when held
      (put held sub nil)
      (when (empty? held) (put registrations (sub :view) nil)))
    (unless (sub :notified)
      (put sub :notified true)
      (ev/give (sub :wake) true))))

(defn publish
  "Coalesces a topic without waiting for a reader; control has its own priority slot."
  [view topic]
  (each sub (keys (get registrations view {}))
    (when (index-of topic (sub :topics))
      (if (= topic (sub :control-topic))
        (put sub :control topic)
        (put (sub :pending) topic true))
      # There is at most one outstanding wake token, so this give never parks.
      (unless (sub :notified)
        (put sub :notified true)
        (ev/give (sub :wake) true)))))

(defn take
  "Takes the latest invalidation, preferring control over accumulated data."
  [sub]
  (while (and (not (sub :closed)) (not (sub :control)) (empty? (sub :pending)))
    (ev/take (sub :wake))
    (put sub :notified false))
  (unless (sub :closed)
    (if-let [control (sub :control)]
      (do (put sub :control nil) control)
      (let [topic (first (keys (sub :pending)))]
        (put (sub :pending) topic nil) topic))))

(defn count
  "Returns the live subscriber count, optionally restricted to a topic."
  [view &opt topic]
  (length (filter |(or (not topic) (index-of topic ($ :topics)))
                  (keys (get registrations view {})))))

(defn drain
  "Waits for subscribed streams to finish their control response, up to seconds."
  [view topic seconds]
  (ev/with-deadline seconds
    (while (pos? (count view topic)) (ev/sleep 0.005))))
