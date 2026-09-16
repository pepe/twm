# Serializable peer intent and generation identity. Process handles belong to
# Demiurge's observer, never to the state copied to workers or returned by RPC.

(defn record
  "Returns (and, when absent, creates) the lifecycle record for a peer."
  [state peer]
  (def view (state :view))
  (unless (view :lifetimes) (put view :lifetimes @{}))
  (or (get-in view [:lifetimes peer])
      (let [entry @{:generation 0 :desired :stopped :phase :exited :failures 0}]
        (put (view :lifetimes) peer entry)
        entry)))

(defn current?
  "Whether a completion belongs to the peer's current generation."
  [state peer generation]
  (or (nil? generation)
      (= generation (get-in state [:view :lifetimes peer :generation]))))

(defn reserve
  "Reserves one spawn synchronously, or coalesces intent behind a live owner."
  [state peer]
  (def entry (record state peer))
  (put entry :desired :running)
  (if (get-in state [:view :spawned peer])
    (do (when (= :stopping (entry :phase)) (put entry :restart true)) nil)
    (do
      (put entry :generation (inc (entry :generation)))
      (put entry :phase :starting)
      (put entry :since (os/clock))
      (put entry :restart nil)
      (put (get-in state [:view :spawned]) peer :boot)
      (entry :generation))))

(defn stop
  "Withdraws intent but retains ownership until the exact process is reaped."
  [state peer]
  (def entry (record state peer))
  (put entry :desired :stopped)
  (put entry :restart nil)
  (when (get-in state [:view :spawned peer])
    (put entry :phase :stopping)
    (put (get-in state [:view :spawned]) peer :stopping)))

(defn ready
  "Accepts readiness only from the starting generation, never from a stopped one."
  [state peer generation]
  (when (and (current? state peer generation)
             (= :starting ((record state peer) :phase)))
    (def entry (record state peer))
    (put entry :phase :ready)
    (put entry :ready-at (os/clock))
    (put (get-in state [:view :spawned]) peer :mycelium)))

(defn exited
  "Records a reaped exit and bounded retry delay; returns immediate restart intent."
  [state peer generation code &opt failure]
  (when (current? state peer generation)
    (def entry (record state peer))
    (def restart (entry :restart))
    (def retry (and (= :running (entry :desired))
                   (or restart (= :starting (entry :phase))
                       (and (get-in state [:view :ran])
                            (index-of peer (get state :autostart []))))))
    (def failures (if (and (entry :ready-at)
                           (> (- (os/clock) (entry :ready-at)) 30))
                     1 (inc (entry :failures))))
    (merge-into entry
                {:phase (if (and (= code 0) (not failure)) :exited :failed)
                 :desired (if retry :running :stopped)
                 :exit-code code :failure failure :exited-at (os/clock)
                 :ready-at nil :restart nil :failures failures
                 :retry-at (+ (os/clock) (min 30 (math/pow 2 (min 5 failures))))})
    restart))
