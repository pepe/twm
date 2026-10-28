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
  ```
  Installs a snapshot's values in `view` all at once, prepared by
  `prepare` when given: a preparation that fails leaves the view as it
  was.

  The newest snapshot is always the last installed. A symbiont has one
  in flight at a time, and every refresh asked for while it is out waits
  for the next, so they are taken, and arrive, in order.
  ```
  [view {:values values} &opt prepare]
  (assert (dictionary? values) "Invalid Tree snapshot")
  (def draft (merge @{} view))
  (merge-into draft values)
  (when prepare (prepare draft))
  (merge-into view draft)
  # Cleared on the view itself: a nil put takes the key out of the draft,
  # and a key that is not there is not merged.
  (put view :projection/error nil)
  view)

(defn- ^unready/failed
  "Settles every view not yet shown as failed, so no first paint waits on it."
  [failure]
  (make-effect
    (fn [_ state _]
      (each space (spaces state)
        (when-let [view (space :view)]
          (unless (get (readiness/status view) :ready)
            (readiness/settle view :failed failure)))))
    "fail unready projection"))

(defn- ^pump []
  (var batch nil)
  (make-event
    {:update
     (fn [_ state]
       (set batch (state :projection/pending))
       (put state :projection/pending @[]))
     :watch
     (fn [_ state _]
       (def requested @{})
       (each request batch
         (each coll (if (dictionary? (request :colls)) (keys (request :colls)) (request :colls))
           (put requested coll true)))
       (def colls (keys requested))
       (def tree (state :tree))
       (if (nil? (get tree :stream))
         # A symbiont whose line to the Tree is closed is standing down:
         # its goodbye closed it. What it was asked to refresh would be
         # shown to nobody -- a logout's own session notice reaches the
         # dashboard that is leaving -- so it is let go, and not reported
         # as a projection that failed. Nothing opens the line again, so a
         # line that broke any other way has said so once already, with
         # the fetch that broke it; every later fetch would only say it
         # again.
         (make-event
           {:update
            (fn [_ state]
              (put state :projection/pending @[])
              (put state :projection/running false))
            :watch [(^unready/failed "RPC connection closed")]}
           "let Tree projection go")
       (producer
         (def [ok answer]
           # The owner says whose session `:cap/session` should be. A tree
           # keeping one for the whole Thicket ignores it.
           (protect (:snapshot tree colls (session/owner state))))
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
                    (do (each [view draft] drafts
                          (merge-into view draft)
                          (put view :projection/error nil))
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
                     (^unready/failed failure)
                     ;(if-let [failed (state :projection/failed)] [failed] [])])
                 ;(if (state :projection/running) [(^pump)] [])])}
             "install Tree projection")))))}
    "fetch Tree projection"))

(defn ^refresh
  "Coalesces projection requests, fetches outside the manager, then runs successors."
  [colls & after]
  (var start false)
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
       (unless (state :projection/running)
         (put state :projection/running true)
         (set start true)))
     :watch (fn [&] (if start (^pump)))}
    "request Tree projection"))
