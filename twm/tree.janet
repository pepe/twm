(import ./thicket :prefix "")
(import ./sentry :as sentry)

(defn ^peer/restore
  "Restores the RPC URL for a connected peer."
  [peer]
  (make-update
    (fn [_ state]
      ((>update peer |(string ($ :host) ":" ($ :port))) state))
    (. "restore peer " peer)))

(defn ^peer/disconnect
  "Closes a peer and restores its RPC URL in manager state."
  [peer]
  (make-event
    {:watch
     (fn [_ state _]
       (if ((??? {peer table?}) state)
         (^peer/restore peer)))
     :effect
     (fn [_ state _]
       (when-let [p ((??? table?) (state peer))
                  cl (p :close)]
         (protect (cl p))))}
    (. "disconnect peer " peer)))

(defn register
  "Connects a registered peer and returns its current session capability."
  [peer session & successors]
  (produce (^peer/connect peer ;successors))
  (sentry/=>session/?eq session))

(defn deregister
  "Builds deregistration events, ending with safe peer disconnection."
  [peer & before]
  (tuple ;before (^peer/disconnect peer)))

(defn ^session/save
  ```
  Saves a session through `update-session` and then runs refresh events.
  The adapter receives manager state and the new session.
  ```
  [session update-session & refresh]
  (make-event
    {:update
     (fn [_ state]
       (update-session state session))
     :watch refresh}
    "save session"))

(defn session/new
  "Builds the standard tree response events for a newly published session."
  [session save-event &opt owner]
  [(log (if owner (. owner " saves session") "saves session"))
   save-event])

(defn session/cap
  "Returns an HTTP cookie capability for the stored session."
  [session]
  (sentry/=>session/?eq session))

(defn run
  "Runs Tree setup events followed by the shared RPC and readiness lifecycle."
  [config & setup]
  (-> config
      (make-manager on-error)
      (:transact ;setup RPC Ready)
      :await))

(defmacro main
  "Defines a Tree executable entry point around `run`."
  [config & setup]
  ~(defn main
     "Main entry into a Tree executable."
     [_ & _args]
     (,run ,config ,;setup)
     (,os/exit 0)))
