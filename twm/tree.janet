(import ./thicket :prefix "")
(import ./sentry :as sentry)
(import gp/ownership)

(defn ^peer/restore
  "Restores the RPC URL for a connected peer."
  [peer]
  (make-update
    (fn [_ state]
      ((>update peer server/address) state))
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
  ```
  Returns an HTTP capability for the stored session.

  What is stored is either one session string, as a tree kept before a
  door could hold several, or the door's live tokens as kept by
  `sessions/record`. Either way the capability admits the cookie, and the
  tokens also as a bearer.
  ```
  [session]
  (if (dictionary? session)
    (sentry/=>session/?live session)
    (sentry/=>session/?eq session)))

(defn sessions/record
  ```
  Records what `:session/new` was told in `sessions`, the tree's table of
  live tokens by owner, and returns it.

  The call keeps its old shape -- a session and its owner -- so a sentry
  and a tree of different ages still understand each other, and says more
  in an optional last argument:

  - a token, with `{:holder h}` or nothing: one more live session at the
    owner's door, held by `h`; a sign-in never ends anyone else's;
  - the empty string with `{:token t}`: that one session ends;
  - the empty string with `{:holder h}`: every session `h` holds ends;
  - the empty string alone: every session of the door ends, which is what
    it always meant.
  ```
  [sessions session owner &opt how]
  (def live (or (get sessions owner) @{}))
  (put sessions owner live)
  (def {:holder holder :token token} (or how {}))
  (cond
    (present-string? session) (put live session (or holder true))
    token (put live token nil)
    holder (eachp [t h] (table/clone live) (when (= h holder) (put live t nil)))
    (table/clear live))
  sessions)

(def Settling
  ```
  Writes the store on the beat, and only when there is something to write.

  Durability used to be every event's own business: each one that changed
  anything wrote the whole image and collected, so one command that stops
  a track, marks a todo done and focuses the next did it three times in as
  many hundredths of a second. Events say `Changed` now, and this listens.

  A burst becomes one write. What it costs is a tick of durability against
  an unclean death; a clean one writes on the way out.

  A quiet tree still writes nothing, but it may not also collect nothing:
  the beat that watches for dirt allocates on every tick, and with the
  store's collector switched off between flushes a tree nobody touches
  climbs until Janet's own interval trips, ~2GiB away. So the reclaiming
  gets a slower beat of its own, and stands down on the ticks where `Flush`
  is going to do it anyway.
  ```
  (heart-beat
    [Flush] (fn [_ state] (state :dirty))
    [Collect] (fn [heart state] (and (not (state :dirty))
                                     (zero? (mod heart 60))))))

(defn stop
  ```
  RPC function that writes the store, closes peers and stops the server.

  The write is the whole reason this is not `close-peers-stop`. While
  every event flushed for itself nothing was ever pending, so stopping had
  nothing to say about the store; with writing gathered onto a beat there
  is always up to a tick of it unwritten, and going without it is leaving
  it behind. Effects run before the exit's producer is given its turn, so
  the image is down before anyone is asked to leave.
  ```
  [&]
  (produce Flush
           ClosePeers
           (log "RPC server going down")
           Stop)
  :ok)

(defn run
  ```
  Runs Tree setup, then announces readiness after its RPC listener binds.

  `Settling` goes in after the project's setup, because it watches a store
  the setup is what creates.
  ```
  [config & setup]
  (supervisor/arm)
  # Acquire before PrepareStore can load or flush. Keep the non-marshallable
  # kernel handle outside manager state; a killed process releases it too.
  (def claim (ownership/acquire (string (path/abspath (config :image)) ".lock")))
  (defer (ownership/release claim)
    (-> config
        (make-manager on-error)
        (:transact ;setup Settling (^rpc/start AetherReady))
        :await)))

(defmacro main
  "Defines a Tree executable entry point around `run`."
  [config & setup]
  ~(defn main
     "Main entry into a Tree executable."
     [_ & _args]
     (,run ,config ,;setup)
     (,os/exit 0)))
