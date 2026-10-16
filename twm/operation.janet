(import ./app :prefix "")

(defn status
  "A detached operation receipt; nil means expired or unknown, never completed."
  [view id]
  (when-let [record (get-in view [:operations id])]
    (freeze (merge @{} record))))

(defn step
  "Names a synchronous event step and waits for application, including failures."
  [record phase events]
  (put record :phase phase)
  (produce/applied events))

(defn ^start
  "Reserves the single maintenance slot and records the eventual outcome of work."
  [record work]
  (make-event
    {:update
     (fn [_ {:view view}]
       (assert (not (view :operation)) "Another maintenance operation is still active")
       (unless (view :operations) (put view :operations @{}))
       (def history (view :operations))
       (when (>= (length history) 64)
         (def oldest (first (sort-by |(get (history $) :accepted-at) (keys history))))
         (put history oldest nil))
       (put history (record :id) record)
       (put view :operation (record :id)))
     :watch
     (fn [_ state _]
       (producer
         (put record :status :running)
         (def [ok result] (protect (work state record)))
         (put record :status (if ok :completed :failed))
         (put record :finished-at (os/time))
         (unless ok
           (put record :failure (string/format "%j" result))
           (eprin (string "Operation " (record :id) " " (record :kind)
                          " failed at " (record :phase) ": " (record :failure) "\n")))
         (put (state :view) :operation nil)
         (put (state :view) :releasing false)))}
    "maintenance operation"))

(defn submit
  "Accepts work atomically and returns its ID, not a claim that it has completed."
  [kind work]
  (def record @{:id (string (util/bin2hex (os/cryptorand 12))) :kind kind
                :status :accepted :phase :accepted :accepted-at (os/time)})
  (produce/applied [(^start record work)])
  {:status :accepted :id (record :id) :kind kind})
