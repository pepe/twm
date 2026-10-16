(import ./app :prefix "")

(defn ^ready
  "Opens the shared readiness gate after the complete initial projection is installed."
  []
  (make-effect
    (fn [_ state _]
      (each space (spaces state)
        (when-let [view (space :view)] (readiness/settle view :ready))))
    "projection ready"))

(defn install
  "Atomically installs a snapshot's fields; revisions never move backwards."
  [view {:epoch epoch :revision revision :values values} &opt prepare]
  (assert (and epoch (number? revision) (dictionary? values)) "Invalid Tree snapshot")
  (def draft (merge @{} view))
  (def revisions (if (= epoch (view :projection/epoch))
                   (merge @{} (get view :projection/revisions {})) @{}))
  (put draft :projection/revisions revisions)
  (put draft :projection/epoch epoch)
  (each [coll value] (pairs values)
    (when (>= revision (get revisions coll -1))
      (put draft coll value)
      (put revisions coll revision)))
  (when prepare (prepare draft))
  (put draft :projection/error nil)
  (merge-into view draft)
  view)

(defn- ^pump []
  (var batch nil)
  (make-event
    {:update
     (fn [_ state]
       (set batch (state :projection/pending))
       (put state :projection/pending @[])
       (put state :projection/since (os/clock :monotonic))
       (put state :projection/stall-said nil))
     :watch
     (fn [_ state _]
       (def requested @{})
       (each request batch
         (each coll (if (dictionary? (request :colls)) (keys (request :colls)) (request :colls))
           (put requested coll true)))
       (def colls (keys requested))
       (def tree (state :tree))
       (producer
         (def [ok answer]
           # The owner says whose session `:cap/session` should be. A tree
           # keeping one for the whole Thicket ignores it.
           (protect (ev/with-deadline 8 (:snapshot tree colls (session/owner state)))))
         (var applied false)
         (var failure answer)
         (produce
           (make-event
             {:update
              (fn [_ state]
                (when ok
                  (def [accepted drafts]
                    (protect
                      (seq [space :in (spaces state) :when (space :view)]
                        [(space :view)
                         (install (merge @{} (space :view)) answer
                                  (space :projection/prepare))])))
                  (if accepted
                    (do (each [view draft] drafts (merge-into view draft))
                        (set applied true))
                    (set failure drafts)))
                (unless applied
                  (each space (spaces state)
                    (when-let [view (space :view)]
                      (put view :projection/error (string failure)))))
                (put state :projection/running (present? (state :projection/pending))))
              :watch
              (fn [_ state _]
                [;(if applied
                    [;(map ^notify/send colls)
                     ;(flatten (map |(get $ :after []) batch))]
                    [(log "Tree projection failed: " failure)
                     (make-effect
                       (fn [_ state _]
                         (each space (spaces state)
                           (when-let [view (space :view)]
                             (unless (get (readiness/status view) :ready)
                               (readiness/settle view :failed failure))))))
                     ;(if-let [failed (state :projection/failed)] [failed] [])])
                 ;(if (state :projection/running) [(^pump)] [])])}
             "install Tree projection"))))}
    "fetch Tree projection"))

(def- stall/patience
  ```
  Seconds a snapshot may be out before refreshes queuing behind it are
  said to be stalled.

  A fetch gives up after eight, and installing it is one event. Once far
  past that, the fetch has not reported back and never will: every later
  refresh only joins the queue, and the view goes on showing the past
  with nothing in the log -- the one fault here that is otherwise silent.
  ```
  30)

(defn ^refresh
  "Coalesces projection requests, fetches outside the manager, then runs successors."
  [colls & after]
  (var start false)
  (var stalled nil)
  (make-event
    {:update
     (fn [_ state]
       (unless (state :projection/pending) (put state :projection/pending @[]))
       (def pending (state :projection/pending))
       (if (empty? after)
         (do
           # A slow snapshot retains one set of dirty topics, not an
           # unbounded queue of identical invalidation requests.
           (def request (or (find |(empty? ($ :after)) pending)
                            (let [r @{:colls @{} :after []}] (array/push pending r) r)))
           (each coll colls (put (request :colls) coll true)))
         (array/push pending {:colls colls :after after}))
       (if (state :projection/running)
         (let [now (os/clock :monotonic)
               waited (- now (get state :projection/since now))]
           (when (and (> waited stall/patience)
                      (not (state :projection/stall-said)))
             (put state :projection/stall-said true)
             (set stalled waited)))
         (do (put state :projection/running true)
             (set start true))))
     :watch (fn [&]
              (cond
                start (^pump)
                stalled (log "Tree projection has waited "
                             (math/round stalled)
                             "s for a snapshot; refreshes are queuing behind it")))}
    "request Tree projection"))
