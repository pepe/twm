(import ./thicket :prefix "")
(import ./lifecycle)
(import ./operation :export true)
(import ./artifact :export true)
(import gp/atomic :export true)
(import gp/ownership)
(import jhydro)
(use spork/sh-dsl spork/sh
     spork/declare-cc spork/cc spork/build-rules)

(setdyn *rpc-defines* [:view])

(def- peer/running
  ```
  The process of every peer the Demiurge currently holds, keyed by peer.

  A process handle is live machinery and the Demiurge's state is marshalled
  whole whenever it hands work to a thread, so what it is holding is kept
  beside the state rather than in it -- the same reason a living space
  keeps its listeners outside.
  ```
  @{})

(def peer/patience
  ```
  Seconds a peer is given to go once it has been asked to.

  Asking is not making. A peer that does not answer its mycelium address
  never hears the asking at all, and one that hears it can still fail to
  reach its own exit; either way it goes on holding every address it
  bound, and the next one raised in its place cannot listen. After this
  much waiting the Demiurge stops asking.
  ```
  10)

(defn peer/config
  "The configuration of `peer` as its thicket declares it."
  [state peer]
  (get-in state [:config :symbionts peer] {}))

(defn peer/subthicket
  ```
  How to raise `peer` when it is the Demiurge of a thicket of its own --
  a subthicket -- or nil for every other peer.

  A subthicket is a thicket that can live on its own: it is bootstrapped,
  released and driven exactly as one that has no parent. Under a parent it
  is raised from its own checkout with its own whole configuration, and
  the parent supervises it as a peer. Its `:subthicket` says where:
  `:build-path` its checkout, `:conf` its configuration (`conf.jdn` in the
  checkout when left out), `:environment` the Janet environment it runs
  in, and `:log` the file its stderr goes to.
  ```
  [state peer]
  (get (peer/config state peer) :subthicket))

(def subthicket/defaults
  ```
  What supervising a subthicket asks for unless its configuration says
  otherwise.

  `:shutdown` is long because a subthicket asked to stop finishes the
  maintenance it is in first, and then stops its own peers with their own
  patience; killing it before that is what leaves peers behind. `:boot`
  is the time it is given to say it is ready.
  ```
  {:shutdown 300 :boot 120})

(defn peer/budget
  ```
  Seconds `peer` is given to go once asked, before it is made to.

  Its own `:shutdown` when it declares one; a subthicket's default; else
  the Demiurge's `:stop-timeout`, else `peer/patience`.
  ```
  [state peer]
  (or (get (peer/config state peer) :shutdown)
      (when (peer/subthicket state peer) (subthicket/defaults :shutdown))
      (state :stop-timeout)
      peer/patience))

(defn peers/budget
  "The longest budget among `peers`, or among the spawned ones."
  [state &opt peers]
  (default peers (keys (get-in state [:view :spawned] {})))
  (max (or (state :stop-timeout) peer/patience) ;(map |(peer/budget state $) peers)))

(defn peer/boot-window
  "Seconds `peer` is given from its spawn to its readiness."
  [state peer]
  (or (get-in (peer/config state peer) [:supervision :boot])
      (when (peer/subthicket state peer) (subthicket/defaults :boot))
      30))

(defn peer/heartbeat?
  ```
  Whether missed heartbeats may restart `peer`.

  Not a subthicket's, by default. Its heartbeat is answered by the same
  event loop that compiles its peers in a release, and a few seconds of
  compiling are not a stalled Demiurge. Restarting it there would end the
  release in the middle; it is restarted when its process exits instead.
  ```
  [state peer]
  (def supervision (get (peer/config state peer) :supervision {}))
  (if (has-key? supervision :heartbeat)
    (truthy? (supervision :heartbeat))
    (not (peer/subthicket state peer))))

(defn subthicket/psk
  ```
  The key one subthicket and its parent speak with: the parent's own key
  hashed with the subthicket's name.

  Each subthicket knows only its own. The parent's key would let it speak
  to every sibling's door, and to the parent's whole mycelium besides.

  The key goes into the hashed bytes rather than into `hash/hash`'s own
  key argument: jhydro's binding tests the argument after the key to
  decide whether a key was given, so whether the key is used at all
  depends on whatever lies past the arguments, and differs from one call
  to the next. Hydro's hash is a sponge, which no message can be extended
  past, so hashing the key ahead of the name keys it soundly; the zero
  byte keeps one key and name from reading as another.
  ```
  [psk peer]
  (string (jhydro/hash/hash 32 (string psk "\0" peer) "twmsubth")))

(defn peer/url
  "The address the Demiurge reaches `peer` on."
  [state peer]
  (def held (state peer))
  (if (string? held) held (server/address held)))

(defn subthicket/relation-file
  "The file telling the subthicket `peer` how its parent reaches it."
  [state peer]
  (path/join (state :data-path) "subthickets" (. (peer/file-name peer) ".jdn")))

(defn peer/spit-conf
  "Spits the config for the `peer`"
  [state peer &opt nav]
  (default nav (state :nav/symbiont))
  (let [conf (jdn/render ((nav peer) (state :config)))
        file (. "conf." (peer/file-name peer) ".jdn")]
    (spit file conf)
    file))

(defn peer/build-sha-file
  "Path of the source revision recorded for a built `peer`."
  [build-path peer]
  (path/join build-path "_build" "develop"
             (. (peer/file-name peer) ".sha")))


(defn peer/release-sha-file
  "Path of the source revision recorded for a selectively deployed `peer`."
  [release-path peer]
  (path/join release-path (. (peer/file-name peer) ".sha")))

(defn peer/buildable?
  "Whether `peer` is explicitly configured as a Demiurge build target."
  [state peer]
  (some |(= peer $) (or (state :builds) @[])))

(def subthicket/variable
  ```
  The environment variable naming the relation file of a Demiurge raised
  as a subthicket. Its absence is how a Demiurge knows it has no parent.
  ```
  "TWM_PARENT")

(defn- subthicket/spawn
  ```
  Raises the subthicket `peer` as `sub` describes it, with the inherited
  `env`, writing first the relation that tells it how its parent reaches
  it.

  It runs in its own checkout. Janet's `:cd` is not built for musl, so
  outside Windows the command goes through `sh`, which changes directory
  and `exec`s it: the process the parent holds and waits on is the
  subthicket's Demiurge itself, not a shell in front of it.
  ```
  [state peer sub env]
  (def {:build-path bp :conf conf :environment ep :log log} sub)
  (assert (present-string? bp) (. "Subthicket " peer " needs a :build-path"))
  (def relation (subthicket/relation-file state peer))
  (def dir (path/dirname relation))
  (unless (os/stat dir) (os/mkdir dir))
  (os/chmod dir 8r700)
  (atomic/write relation
                (jdn/render {:name peer :parent (state :name)
                             :rpc (peer/url state peer)
                             :psk (subthicket/psk (state :psk) peer)}))
  (os/chmod relation 8r600)
  (put env "CONF" (or conf (path/join bp "conf.jdn")))
  (put env subthicket/variable relation)
  (when ep
    (put env "JANET_PATH" ep)
    (put env "PATH" (string (path/join ep "bin")
                            (if (= :windows (os/which)) ";" ":")
                            (os/getenv "PATH" ""))))
  (def cmd [(if ep (path/join ep "bin" "janet") (dyn *executable* "janet"))
            (path/join bp "demiurge.janet")])
  (def err (when log (file/open log :a)))
  (when err (put env :err err))
  (defer (when err (file/close err))
    (if (= :windows (os/which))
      (os/spawn cmd :pe (put env :cd bp))
      (os/spawn ["/bin/sh" "-c" `cd "$1" && shift && exec "$@"` "sh" bp ;cmd]
                :pe env))))

(defn ^subthicket/run-peers
  ```
  Asks the subthicket `peer`, just connected, to run its own peers.

  A Demiurge raises nothing of its own accord: started alone, it is asked
  to by whoever started it. A subthicket with `:run-peers` is asked by its
  parent each time it is ready, so one the parent raised again after it
  died comes back whole, peers and all.
  ```
  [peer]
  (make-watch
    (fn [_ state _]
      (def client (state peer))
      (producer
        (def [ok answer] (protect (:run-peers client)))
        (produce (log "Asked " peer " to run its peers: " (if ok answer (string "failed, " answer))))))
    (. "run peers of " peer)))

(defn peer/pipe-out
  ```
  Spawns the peer process with its stdout piped, which is the Aether the
  demiurge reads it on.

  Its stdin is piped too and never written to. That is a closed door, not
  an unfinished one: peers run under `janet -d`, and a debugger inheriting
  the terminal would take the keystrokes meant for the demiurge.
  ```
  [state peer cmd flags]
  (if-let [spawn (state :spawn-process)]
    (spawn cmd flags)
    (do
      (def fs (keyword (string/replace-all "x" "" (string flags)) :e))
      (def env (merge (os/environ)
                      {supervised/variable "1" :in :pipe :out :pipe}))
      # The parent of this Demiurge is not the parent of its peers.
      (put env subthicket/variable nil)
      (if-let [sub (peer/subthicket state peer)]
        (subthicket/spawn state peer sub env)
        (os/spawn cmd fs (put env "CONF" (peer/spit-conf state peer)))))))

(defn ^save-sha
  "Event that saves git sha"
  [sha]
  (make-update
    (fn [_ {:view view}]
      ((>put :sha sha) view))
    "save sha"))

(define-event SetReleasedSHA
  "Writes the current SHA to file"
  {:effect
   (fn [_ {:view view :release-path rp} _]
     (when-let [sha (view :sha)]
       (atomic/write (path/abspath (path/join rp "release.sha")) sha)
       (put view :release-sha sha)))})

(define-watch PullGetSHA
  "Save in the state the latest shas of the repository"
  [_ {:dry dry} _]
  (producer
    (if-not dry ($< git pull))
    (produce (^save-sha (string ($<_ git rev-parse HEAD))))))

(define-event Released
  "Marks the end of releasing"
  {:update
   (fn [_ {:view view}] ((>put :releasing false) view))
   :watch PullGetSHA})

(defn ^peer/remove
  "Clears reaped ownership, ignoring completions from an older generation."
  [peer &opt generation]
  (make-update
    (fn [_ state]
      (when (lifecycle/current? state peer generation)
        (def {:view {:spawned spawned :misses misses :activity activity}} state)
        (put misses peer nil)
        (put activity peer nil)
        (put spawned peer nil)
        (def ep (state peer))
        (when (dictionary? ep)
          (protect (:close ep))
          (put state peer (server/address ep)))))
    (. "remove peer " peer)))

(defn- peer/places
  ```
  Every place `peer` holds -- the one it answers to by name, and any it
  was given to keep besides.

  One reading of this, so that what a peer may report free and what is
  handed back on its behalf cannot drift apart.
  ```
  [state peer]
  [peer ;(keys (get (((state :nav/symbiont) peer) (state :config))
                    :spaces {}))])

(defn ^place/return
  "Returns a confirmed vacant place to its guardian without blocking the manager."
  [peer]
  (make-watch
    (fn [_ state _]
      (def guardian (get-in state [:config :symbionts peer :guarded-by]))
      (def client (if guardian (state guardian)))
      (producer
        (when (and client (dictionary? client))
          (def [ok err] (protect (:space/resume client peer)))
          (unless ok (produce (log "Cannot return " peer " to " guardian ": " err))))))
    (. "return place of " peer)))

(defn ^peer/insist
  "Bounds departure of the captured process; its observer alone confirms exit."
  [peer &opt generation]
  (make-watch
    (fn [_ state _]
      (def asked (peer/running peer))
      (producer
        (ev/sleep (peer/budget state peer))
        (def current (peer/running peer))
        (when (and current (or (not asked) (= asked current))
                   (lifecycle/current? state peer generation))
          (produce (log peer " did not exit; ending generation " generation))
          (def [ok err] (protect (os/proc-kill current)))
          (unless ok (produce (log "Cannot end " peer ": " err))))))
    (. "insist " peer)))

(defn ^peer/stop
  "Requests departure without releasing ownership before the process is reaped."
  [peer]
  (make-event
    {:update (fn [_ state] (lifecycle/stop state peer))
     :watch
     (fn [_ state _]
       (def generation ((lifecycle/record state peer) :generation))
       (def pc (state peer))
       [(^peer/insist peer generation)
        (make-watch
          (producer
            (when (dictionary? pc)
              (def [ok err] (protect (:stop pc)))
              (unless ok (produce (log "Stop request for " peer " failed: " err)))
              (protect (:close pc)))))] )}
    (. "stop peer " peer)))

(define-event StopPeers
  "Sends stop RPC to all peers"
  {:update (fn [_ state]
             (put (state :view) :ran false)
             (each peer (keys (get-in state [:view :lifetimes] {}))
               (lifecycle/stop state peer)))
   :watch
   (fn [_ {:view {:spawned spawned}} _]
     (seq [[peer _] :pairs spawned] (^peer/stop peer)))})

(defn ^peer/clear
  "Resets the missed heartbeat count for a peer."
  [peer]
  (make-update
    (def-state _
      (=<> :view (>update :misses (>put peer 0))))
    (. "clear missed " peer)))

(defn ^peer/no-active
  "Resets the missed activity heartbeat count for a peer."
  [peer]
  (make-update
    (def-state _
      (=<> :view (>update :activity (>put peer nil))))
    (. "no-active missed " peer)))

(defn ^peer/save-spawned
  "Saves readiness only for the current process generation."
  [peer phase &opt generation]
  (make-update
    (fn [_ state]
      (if generation
        (lifecycle/ready state peer generation)
        (put (get-in state [:view :spawned]) peer phase)))
    (. "save spawned peer " peer)))

(defn ^peer/connect
  "Connects to the current generation with a bounded retry budget."
  [peer &opt succ generation]
  (make-event
    {:update
     (fn [_ state]
       (when (lifecycle/current? state peer generation)
         (def {:name name} state)
         (def psk (if (peer/subthicket state peer)
                    (subthicket/psk (state :psk) peer)
                    (state :psk)))
         (def url (state peer))
         (when (string? url)
           (def [host port] (server/host-port url))
           (put state peer (make rpc/Client :host host :port port :psk psk :name name)))))
     :watch
     (fn [_ state _]
       (def client (state peer))
       (producer
         (var connected false)
         (loop [attempt :range [0 10]
                :while (and (not connected) (lifecycle/current? state peer generation))]
           (set connected (first (protect (ev/with-deadline 1 (:open client)))))
           (unless connected (ev/sleep (* (inc attempt) 0.1))))
         (when (and connected (lifecycle/current? state peer generation))
           (produce (log peer " connected") (or succ Empty)))
         (unless connected (produce (log peer " could not connect")))))}
    (. "connect peer " peer)))

(defn ^peer/run
  "Reserves one generation, observes it to reap, then permits a successor."
  [group &opt peer cmd flags]
  (var generation nil)
  (var launch nil)
  (make-event
    {:update (fn [_ state]
               (def entry (lifecycle/record state group))
               (when cmd (put entry :launch [peer cmd flags]))
               (set launch (entry :launch))
               (set generation (lifecycle/reserve state group)))
     :watch
     (fn [_ state _]
       (when generation
         (producer
           (def [saved-peer saved-cmd saved-flags] (or launch []))
           (default peer (or saved-peer group))
           (var proc nil)
           (var exit-code nil)
           (var skipped 0)
           (def [ok failure]
             (protect
               (def [_ _ [ecmd eflags]] ((state :entries) peer))
               (default cmd (or saved-cmd ecmd))
               (default flags (or saved-flags eflags))
               (def [identified active]
                 (protect (when (and (state :build-path) (not (state :spawn-process)))
                   (if (state :builder)
                     (artifact/read-installed (first cmd))
                     {:mode :interpreted :source (artifact/source (state :build-path))}))))
               (set proc (peer/pipe-out state peer cmd flags))
               (put (lifecycle/record state group) :active
                    (if identified active {:status :unknown :failure (string active)}))
               (put peer/running group proc)
               (def sub (peer/subthicket state group))
               (def next-message
                 (if sub
                   (aether/scanner (proc :out) |(+= skipped $))
                   |(aether/read-message (proc :out))))
               (forever
                 (def message (next-message))
                 (when (lifecycle/current? state group generation)
                   (if sub
                     # A subthicket is another thicket's Demiurge: it says
                     # it is ready, and nothing it says beyond that is
                     # allowed to cost it its life.
                     (match message
                       {:op :ready}
                       (produce (^peer/connect group
                                  (make-watch [(^peer/save-spawned group :mycelium generation)
                                               ;(if (sub :run-peers) [(^subthicket/run-peers group)] [])]
                                              (. "subthicket " group " ready"))
                                  generation))
                       {:op op} (produce (log "Ignored Aether " op " from subthicket " group)))
                   (match message
                     {:op :ready}
                     (produce (^peer/connect group
                                (^peer/save-spawned group :mycelium generation) generation))
                     {:op :spawn :peer target :arg arg}
                     (let [source (((state :nav/symbiont) group) (state :config))
                           allowed @[;(keys (get source :spaces {})) (source :guarded-by)]]
                       (assert (and (keyword? target) (string? arg) (index-of target allowed))
                               (. "Aether spawn from " group " is not permitted."))
                       (let [[_ _ [next-cmd next-flags]] ((state :entries) target)]
                         (produce (^peer/run target target [;next-cmd arg] next-flags))))
                     {:op :left :place place}
                     (do
                       (assert (index-of place (peer/places state group))
                               (. "Aether left from " group " is not permitted."))
                       (produce (^place/return place)))
                     {:op :result} (produce (log "Aether result from " group))
                     {:op op} (produce (log "Reserved Aether operation " op " from " group))))))))
           (def ordinary-eof (and (string? failure)
                                 (string/has-prefix? "Aether stream ended" failure)))
           (when proc
             # An invalid Aether frame is not allowed to strand its owner.
             (unless (or ok ordinary-eof) (protect (os/proc-kill proc)))
             # Spawn never uses :x: a nonzero exit is data, not an exception
             # that skips cleanup. Exactly this observer waits on the handle.
             (set exit-code (os/proc-wait proc))
             (os/proc-close proc)
             (when (= proc (peer/running group)) (put peer/running group nil)))
           (produce
             (make-event
               {:update
                (fn [_ state]
                  (when (lifecycle/current? state group generation)
                    (lifecycle/exited state group generation exit-code
                                      (unless ordinary-eof failure))))
                :watch
                (fn [_ state _]
                  (when (lifecycle/current? state group generation)
                    [(log group " generation " generation " exited: " exit-code
                          (if ordinary-eof "" (string " " failure))
                          (if (pos? skipped)
                            (string ", having written " skipped " bytes besides its Aether")
                            ""))
                     (^peer/remove group generation)
                     ;(if (= :stopped ((lifecycle/record state group) :desired))
                        (map ^place/return (peer/places state group)) [])]))}
               (. "reaped peer " group))))))}
    (. "run peer " (or peer group))))

(defn ^peer/restart
  "Requests replacement; start intent coalesces until confirmed old-process exit."
  [peer]
  (make-watch [(^peer/stop peer) (^peer/run peer)] (. "restart peer " peer)))

(defn ^peers/after-exit
  "Runs successors only after all reserved generations have been reaped."
  [& successors]
  (make-watch
    (fn [_ state _]
      (producer
        (ev/with-deadline (+ (peers/budget state) 5)
          (while (present? (get-in state [:view :spawned]))
            (ev/sleep 0.025)))
        (produce ;successors)))
    "wait for peer exits"))

(define-event RunPeers
  "Runs peers event"
  {:update
   (fn [_ {:view view}] (put view :ran (os/clock)))
   :watch
   (fn [_ {:dry dry :autostart autostart} _]
     (producer
       (unless dry
         (loop [peer :in autostart]
           (produce (^peer/run peer))))))})

(defn ^peer/mark
  "Increments the missed heartbeat count for a peer."
  [peer]
  (make-update
    (def-state _
      (=<> :view :misses
           (>if (=<> peer number?)
                (>update peer inc)
                (>put peer 1))))
    (. "mark missed " peer)))

(defn ^peer/active
  "Saves peer last activity"
  [peer dt]
  (make-update
    (def-state _
      :view :activity (>put peer dt))))

(def ping/patience
  ```
  Seconds a peer is given to answer its heartbeat before the beat is
  counted missed.

  `try` catches an error but not a parking, and those are two different
  peers. One that has died refuses the connection and answers with an
  error, which is counted, and after three brings a restart. One that is
  alive and no longer serving accepts the connection and answers nothing
  at all: unbounded, that ping never returns, no beat is ever counted
  missed, and `CheckPeers` -- which comes round on this same beat -- never
  runs again. The watch that exists to notice a stalled peer is stopped by
  the very peer it was watching, and its other arm, the one that stops a
  peer gone quieter than the thicket's patience, never gets to look.

  Shorter than `peer/patience`: this is a question asked over loopback,
  not a departure being waited on.
  ```
  3)

(defn ^peer/ping
  "Pings outside the manager; stale generations cannot inherit its result."
  [peer]
  (make-watch
    (fn [_ state _]
      (def generation ((lifecycle/record state peer) :generation))
      (def client (state peer))
      (producer
        (def [ok answer] (protect (ev/with-deadline ping/patience (:ping client))))
        (produce
          (make-update
            (fn [_ state]
              (when (and (lifecycle/current? state peer generation)
                         (= :mycelium (get-in state [:view :spawned peer])))
                (def {:view {:misses misses :activity activity}} state)
                (match [ok answer]
                  [true :pong] (do (put misses peer 0) (put activity peer nil))
                  [true [:last-active (dt (epoch? dt))]]
                  (do (put misses peer 0) (put activity peer dt))
                   (put misses peer (inc (get misses peer 0))))))))))
    (. "ping peer " peer)))

(define-watch PingPeers
  "Pings all spawned peers and records heartbeat failures."
  [_ {:view {:spawned peers}} _]
  (seq [[peer phase] :pairs peers
        :when (= phase :mycelium)]
    (^peer/ping peer)))

(define-watch CheckPeers
  "Reconciles wanted peers, bounded startup and current-generation heartbeat state."
  [_ state _]
  (def {:view view :timeout timeout :autostart autostart} state)
  (def result @[])
  (each [peer phase] (pairs (view :spawned))
    (def entry (get-in view [:lifetimes peer] {}))
    (cond
      (and (= phase :boot) (entry :since)
           (> (- (os/clock) (entry :since)) (peer/boot-window state peer)))
      (array/push result (^peer/restart peer))
      (and (= phase :mycelium) (peer/heartbeat? state peer)
           (> (get-in view [:misses peer] 0) 2))
      (array/push result (^peer/restart peer))
      (and (= phase :mycelium) (get-in view [:activity peer])
           (> (- (os/time) (get-in view [:activity peer])) timeout))
      (array/push result (^peer/stop peer))))
  (def wanted (tabseq [peer :in (if (view :ran) (or autostart []) [])] peer true))
  (each [peer entry] (pairs (get view :lifetimes {}))
    (put wanted peer (= :running (entry :desired))))
  (each [peer desired] (pairs wanted)
    (when (and desired (not (get-in view [:spawned peer]))
               (>= (os/clock) (get-in view [:lifetimes peer :retry-at] 0)))
      (array/push result (^peer/run peer))))
  result)

(defn ^peer/deploy
  "Deploys one peer and records the build revision beside its release executable."
  [peer]
  (make-event
    {:effect
     (fn [_ {:build-path bp :release-path rp} _]
       (def pf (peer/file-name peer))
       (def bexep (executable (path/join bp "_build/develop" pf)))
       (def exep (executable (path/join rp pf)))
       (artifact/install bexep exep)
       (atomic/write (peer/release-sha-file rp peer)
                     (slurp (peer/build-sha-file bp peer))))}))

(defn ^peer/deploy-one
  "Deploys one configured peer whose built revision matches the checked-out source."
  [peer]
  (make-watch
    (fn [_ state _]
      (if-not (peer/buildable? state peer)
        (error (. "Cannot deploy " peer
                  "; it is not listed in Demiurge :builds."))
        (let [bp (state :build-path)
              pf (peer/file-name peer)
              artifact (executable (path/join bp "_build/develop" pf))
              sha-file (peer/build-sha-file bp peer)]
          (assert (os/stat artifact)
                  (. "Cannot deploy " peer "; no built executable exists."))
          (assert (os/stat sha-file)
                  (. "Cannot deploy " peer "; no build SHA exists."))
          (assert (= (string/trim (slurp sha-file))
                     (string ($<_ git rev-parse HEAD)))
                  (. "Cannot deploy " peer
                     "; its build SHA does not match the checked-out source."))
          (def metadata (artifact/read-installed artifact))
          (assert (= :verified (metadata :status)) "Build provenance does not match its executable")
          (assert (= (get-in metadata [:source :digest])
                     (get (artifact/source bp) :digest))
                  "Source contents changed after this build; rebuild before deployment")
          (assert (deep= (metadata :dependencies)
                         {:gp (artifact/dependency "gp/events")
                          :twm (artifact/dependency "twm/app")})
                  "Installed dependencies changed after this build; rebuild before deployment")
          (assert (= (metadata :configuration)
                     (artifact/fingerprint (((state :nav/symbiont) peer) (state :config))))
                  "Configuration changed after this build; rebuild before deployment")
          (^peer/deploy peer))))
    (. "deploy peer " peer)))

(define-watch Deploy
  "Deploys the declared peer fleet; CLI handles have a separate build path."
  [_ {:builds builds} _]
  (seq [peer :in builds] (^peer/deploy-one peer)))

(defn ^peer/build
  "Builds one `peer`"
  [peer]
  (make-effect
    (fn [_ state _]
      (def {:entries entries :name name} state)
      (def [e exep _] (entries peer))
      (def rules @{})
      (def conf (((state :nav/symbiont) peer) (state :config)))
      (def provenance (artifact/provenance (state :build-path) conf))
      (def built (executable (path/join (state :build-path) "_build/develop" (peer/file-name peer))))
      # Spork's entry-file timestamp alone cannot see imported code or native
      # dependency changes. Invalidate only this target's generated outputs.
      (each file [built (string built ".c") (string built ".provenance.jdn")
                  (peer/build-sha-file (state :build-path) peer)]
        (when (os/stat file) (os/rm file)))
      (def old-conf (os/getenv "CONF"))
      (defer (os/setenv "CONF" old-conf)
        (with-dyns [*rules* rules
                    *build-root* "_build"]
          (os/setenv "CONF" (peer/spit-conf state peer))
          (declare-project :name (. name "-" peer))
          (declare-executable :entry e :name (. (peer/file-name peer)))
          (build-run rules "build")
          (assert (deep= provenance (artifact/provenance (state :build-path) conf))
                  "Build inputs changed during compilation; artifact is not deployable")
          (artifact/record built provenance)
          (atomic/write (peer/build-sha-file (state :build-path) peer)
                        (get-in provenance [:source :revision])))))
    (. "build peer " peer)))

(defn ^peer/build-one
  "Builds one explicitly configured peer, without deploying or restarting it."
  [peer]
  (make-watch
    (fn [_ state _]
      (if (peer/buildable? state peer)
        (^peer/build peer)
        (error (. "Cannot build " peer
                  "; it is not listed in Demiurge :builds."))))
    (. "build peer " peer)))

(define-watch Build
  "Builds the declared peer fleet, excluding CLI handles in :entries."
  [_ {:builds builds} _]
  (seq [p :in builds] (^peer/build p)))

(defn ^mark-release
  "Marks that release has started"
  [now]
  (make-update
    (fn [_ {:view view}] ((>put :releasing now) view))
    "mark release"))

(define-effect CleanBuild
  "Cleans build aftifacts"
  [_ {:build-path bp} _]
  (rm (path/join bp "_build")))

(defn peers/await-exit
  "Waits for confirmed reaping, not for a stop request to have been accepted."
  [state &opt peer]
  (ev/with-deadline (+ (if peer (peer/budget state peer) (peers/budget state)) 5)
    (while (if peer (get-in state [:view :spawned peer])
             (present? (get-in state [:view :spawned])))
      (ev/sleep 0.025))))

(defn peers/await-ready
  "Completes only when all requested peers have announced and answered readiness."
  [state peers &opt even-when-dry]
  (when (or even-when-dry (not (state :dry)))
    (ev/with-deadline 45
      (while (some |(not= :mycelium (get-in state [:view :spawned $])) peers)
        (ev/sleep 0.025)))))

(defn peer/maintain
  "Performs one peer operation, with applied steps and a real replacement barrier."
  [state record kind peer]
  (case kind
    :peer/build (operation/step record :building [(^peer/build-one peer)])
    :peer/deploy (operation/step record :installing [(^peer/deploy-one peer)])
    :peer/release
    (do
      (operation/step record :installing [(^peer/deploy-one peer)])
      (when (get-in state [:view :spawned peer])
        (operation/step record :stopping [(^mark-release (os/time)) (^peer/restart peer)])
        (peers/await-exit state peer)
        (operation/step record :starting [(^peer/run peer)])
        (peers/await-ready state [peer])))))

(defn ^peer/release-one
  "Runs a selective release with observable failure and completed replacement."
  [peer]
  (make-watch
    (producer (operation/submit :peer/release |(peer/maintain $0 $1 :peer/release peer)))
    (. "release peer " peer)))

(defn ^peer/command
  "CLI maintenance uses the same receipts and returns a failing process exit on failure."
  [kind peer]
  (make-watch
    (fn [_ state _]
      (producer
        (def accepted (operation/submit kind |(peer/maintain $0 $1 kind peer)))
        (var receipt nil)
        (ev/with-deadline 3600
          (while (do (set receipt (operation/status (state :view) (accepted :id)))
                     (index-of (receipt :status) [:accepted :running]))
            (ev/sleep 0.025)))
        (pp receipt)
        (unless (= :completed (receipt :status)) (os/exit 1))))
    "peer maintenance command"))

(defn maintain
  "Performs thicket maintenance without advancing past a failed or unfinished step."
  [state record kind]
  (def ran (get-in state [:view :ran]))
  (case kind
    :pull
    (do
      (unless (state :dry) ($< git pull))
      (operation/step record :source [(^save-sha (string ($<_ git rev-parse HEAD)))]))
    :run-peers
    (do (operation/step record :starting [RunPeers])
        (peers/await-ready state (state :autostart)))
    :stop-peers
    (do (operation/step record :stopping [StopPeers]) (peers/await-exit state))
    :restart-peers
    (do (operation/step record :stopping [StopPeers])
        (peers/await-exit state)
        (operation/step record :starting [RunPeers])
        (peers/await-ready state (state :autostart)))
    :release
    (do
      (operation/step record :preparing [(^mark-release (os/time))
                                        (^save-sha (string ($<_ git rev-parse HEAD)))])
      (when (and (state :builder) (not (state :dry)))
        (operation/step record :building [Build]))
      (operation/step record :stopping [StopPeers])
      (peers/await-exit state)
      (when (and (state :builder) (not (state :dry)))
        (operation/step record :installing [Deploy]))
      (operation/step record :recording [SetReleasedSHA])
      (when ran
        (operation/step record :starting [RunPeers])
        (peers/await-ready state (state :autostart)))
      (operation/step record :ready [Ready]))
    (error (string "Unknown maintenance operation " kind))))

(defn ^release
  "Accepts an observable release, retaining compatibility with event callers."
  [_now]
  (make-watch (producer (operation/submit :release |(maintain $0 $1 :release))) "release"))

(define-event PrepareView
  "Prepares view"
  {:update
   (fn [_ state]
     (def {:builder builder :peers peers
           :release-path rp :build-path bp
           :entries entries} state)
     (def transformer
       (if builder
         (fn [n e]
           (def exe (executable (path/join rp (peer/file-name n))))
           [e exe [[exe] :x]])
         (fn [n e] [e e [["janet" "-d" e] :p]])))
     (def tentries
       (tabseq [[n e] :pairs entries]
         (keyword n) (transformer n e)))
     (merge-into state
                 {:view @{:spawned @{} :misses @{} :activity @{} :lifetimes @{}}
                  :entries tentries}))
   :effect (fn [_ {:view view :build-path bp} _]
             (os/cd bp)
             (setdyn :view view))})

(define-event Leave
  ```
  Stops the Demiurge as one that is going for good: once no maintenance
  is running, its peers are stopped and waited for, each within its
  budget, and then it exits.

  What a parent asks of a subthicket, what a lost parent leaves it to do
  by itself, and what SIGTERM means. A release in progress is finished
  rather than cut, because a Demiurge stopped between stopping its peers
  and installing their successors leaves nothing running at all. No new
  maintenance is accepted while it waits.
  ```
  {:update (fn [_ {:view view}] (put view :leaving true))
   :watch
   (fn [_ state _]
     (producer
       (while (get-in state [:view :operation]) (ev/sleep 0.1))
       (produce StopPeers (^peers/after-exit Stop))))})

(defn guard-releasing
  "Guards the rpc runction for the release"
  [handler]
  (fn [& args]
    (define :view)
    (cond
      (view :leaving) {:status :leaving}
      (view :operation) {:status :busy :id (view :operation)}
      (handler ;args))))

(defr -:state
  "RPC function, that reports the state of the demiurge"
  [guard-releasing]
  (let [ran (view :ran)
        spwnd ((=<> :spawned keys freeze) view)
        sha (view :sha)
        rsha (view :release-sha)]
    (cond
      (and ran spwnd)
      [:running ran spwnd]
      (and sha rsha)
      [:released sha rsha]
      sha
      [:pulled sha]
      [:bootstrapped])))

(defr -:versions
  "Reports source, installed and active identities separately for every peer."
  []
  (var state nil)
  (produce/applied [(make-effect (fn [_ s _] (set state s)))])
  {:source (artifact/source (state :build-path))
   :peers (tabseq [peer :in (state :builds)]
            peer {:installed (artifact/read-installed
                               (executable (path/join (state :release-path) (peer/file-name peer))))
                  :active (when (get-in state [:view :spawned peer])
                            (get-in state [:view :lifetimes peer :active]))
                  :lifecycle (freeze (select-keys (get-in state [:view :lifetimes peer] {})
                                      [:generation :phase :desired :since :ready-at
                                       :failures :exit-code :failure :retry-at]))})})

(defr -:operation
  "Returns the latest receipt for an accepted operation ID."
  []
  (operation/status view (first args)))

(defr +:release
  "RPC function, that starts the release if possible."
  [guard-releasing]
  (operation/submit :release |(maintain $0 $1 :release)))

(defr +:stop-peers
  "RPC function, that stops the peers if possible."
  [guard-releasing]
  (operation/submit :stop-peers |(maintain $0 $1 :stop-peers)))

(defr +:run-peers
  "RPC function, that starts the peers if possible."
  [guard-releasing]
  (operation/submit :run-peers |(maintain $0 $1 :run-peers)))

(defr +:restart-peers
  "RPC function, that starts the peers if possible."
  [guard-releasing]
  (operation/submit :restart-peers |(maintain $0 $1 :restart-peers)))

(defr +:stop
  "RPC function that stops the demiurge."
  [produce-resp ok-resp guard-releasing]
  [StopPeers (^peers/after-exit Stop)])

(defr +:pull
  "RPC function that stops the demiurge."
  [guard-releasing]
  (operation/submit :pull |(maintain $0 $1 :pull)))

(def rpc-funcs
  "RPC functions"
  @{:state -:state
    :release +:release
    :run-peers +:run-peers
    :stop-peers +:stop-peers
    :restart-peers +:restart-peers
    :pull +:pull
    :versions -:versions
    :operation -:operation
    :stop +:stop})

(defn ^bootstrap-arg
  "Saves the bootstrap argument"
  [arg]
  (make-update
    (fn [_ state] (put state :bootstrap (keyword arg)))))

(defn janet/build-steps
  ```
  Steps that build Janet from `source` and install it over the environment.

  `janet-pm full-env` copies the box's own Janet into the environment: the
  interpreter, `libjanet` and the headers every peer is linked against.
  Given a `:janet-source` in `:deploy`, that copy is replaced by a Janet
  built from the named repository and revision, installed with the
  environment as its prefix, so one environment can run a Janet the box
  does not. Without one, the box's Janet stays, as it always has.

  The flags are the box's own: no LTO, which pins every static archive to
  the GCC that wrote it. The source sits beside the checkout rather than
  in it, where it would make the checkout dirty.

  The steps are for `ssh-cmds`, placed after `full-env` and before the
  environment is activated.
  ```
  [source bp env]
  (def {:repo repo :rev rev} source)
  (assert (and (present-string? repo) (present-string? rev))
          ":janet-source needs a :repo and a :rev")
  (def jsp (string bp "-janet"))
  (def make-vars [(string "PREFIX=" (path/posix/join bp env)) "CFLAGS='-fPIC -O2'"])
  [[:rm "-rf" jsp]
   [:git :clone "--quiet" repo jsp]
   [:git :-C jsp :checkout "--quiet" rev]
   [:make :-C jsp "-j4" ;make-vars]
   [:make :-C jsp :test ;make-vars]
   [:make :-C jsp :install ;make-vars]])

(def HeartCheck
  "Heart beat checker function"
  (heart-beat
    [PingPeers CheckPeers]
    (fn :ping [i {:dry dry :view {:releasing releasing}}]
      (and (not dry) (not releasing) (= 0 (mod i 2))))))

(define-update ClearTests
  "Clears the test stats"
  [_ state]
  ((=>
     (>put :test
           @{:start (os/clock)
             :passed 0
             :total 0
             :failing @[]
             :running true})) state))

(defn ^inc
  "Increases test params"
  [param]
  (make-update
    (def-state _
      :test
      (>update param inc))))

(defn ^failed
  "Adds `path` to failed tests"
  [path]
  (make-update
    (def-state _
      :test
      (>update :failing (>add path)))
    (. "failed " path)))

(defn ^test/file
  "Runs one test file and optionally reports its path and result on `done`."
  [path &opt done]
  (make-watch
    (fn [&]
      (def pass
        (zero? (os/execute [(dyn *executable* "janet") "--" path]
                           # Keep both descriptors explicit when stdout is
                           # redirected to stderr (including on POSIX Janet).
                           :p {:out stderr :err stderr})))
      (if done
        (ev/give done [path pass])
        [(^inc :total) (if pass (^inc :passed) (^failed path))]))))

(define-event TestReport
  "Reports on the results of the test"
  {:update (def-state _ :test (>put :running false))
   :watch
   (fn [_ {:test {:start start :passed passed :total total :failing failing}} _]
     (def duration (precise-time (- (os/clock) start)))
     (if (= passed total)
       [(logr "\e[30;102m---------- All tests passed in " duration "! ----------\e[0m")]
       [(logr "\e[97;101m---------- Some tests failed in " duration "! ----------\e[0m\n")
        (logr (string/format "%d of %d passed. Failing scripts:" passed total))
        ;(map (fn [f] (logr "  \e[97;101m" f "\e[0m")) failing)]))})

(define-effect ClearData
  "Cleard the :data-path directory"
  [_ {:data-path dp} _]
  (each f (os/dir dp) (os/rm (path/abspath (path/join dp f)))))

(defn ^test
  "Runs test files once and publishes their result over the Aether."
  [scope & files]
  (make-watch
    (fn [_ state _]
      (producer
        (def done (ev/chan))
        (def failing @[])
        (produce
          (logr "\e[2J\e[H\e[30;103m---------- Running Tests ----------\e[0m")
          ClearTests)
        (loop [f :in files
               :let [path (string "test/" f)]
               :when (string/has-suffix? ".janet" path)]
          (produce/applied [ClearData (^peer/run :tree)])
          (peers/await-ready state [:tree] true)
          (produce (logr "\n----- In file " path " -----") (^test/file path done))
          (def [_ pass] (ev/take done))
          (produce (^inc :total) (if pass (^inc :passed) (^failed path)))
          (if-not pass (array/push failing f))
          (ev/sleep 0.2)
          (produce (^peer/stop :tree))
          # Asked is not gone, and the next file's `ClearData` must not run
          # while the last file's tree is still holding its store. Stopping
          # flushes the image as its final act, so the outgoing tree is
          # writing the very file the incoming one is about to delete --
          # and a delete against a handle another process holds is refused
          # outright on Windows. `ClearData` then fails, the fresh tree
          # `init`s from the last suite's image, and every count a suite
          # asserts is somebody else's. That is the whole of why this
          # suite's results moved from run to run.
          #
          # `peer/running` is the only honest signal: `^peer/run` clears it
          # after `os/proc-wait` returns, which is the process actually
          # reaped rather than merely asked. The wait is bounded because
          # `^peer/insist` ends a peer that outstays its budget, and
          # giving up says so rather than hanging the whole run.
          (var waited 0)
          (while (and (get-in state [:view :spawned :tree]) (< waited (+ (peer/budget state :tree) 2)))
            (ev/sleep 0.05)
            (+= waited 0.05))
          (when (get-in state [:view :spawned :tree])
            (produce
              (logr "  the tree outstayed its stop; " path
                    " leaves its data to the next file"))))
        (produce
          TestReport
          (^aether @{:op :result :body {:scope scope :failing failing}})
          Stop)))))

(defn ^test/names
  "Runs one or more named tests, accepting names with or without `.janet`."
  [& names]
  (apply ^test :focused
         (map (fn [name]
                (if (string/has-suffix? ".janet" name)
                  name
                  (. name ".janet")))
              names)))

(defn ^download
  "Downloads the remote data-path to `dest`"
  [dest]
  (make-effect
    (fn [_ {:host host :data-path dp :name name} _]
      (os/execute ["scp" "-r" (. host ":" dp "/*") dest] :p))
    (. "download to " dest)))

(def subthicket/door-operations
  ```
  What a subthicket's parent may ask of it besides `:ping` and `:stop`:
  the same maintenance its own operators have, and nothing a project adds.
  ```
  [:state :versions :operation :run-peers :stop-peers :restart-peers
   :release :pull])

(defn ^subthicket/door
  ```
  Opens the door a Demiurge raised as a subthicket keeps for its parent,
  as `relation` describes it, then tells the parent it is ready and from
  then on leaves when the parent is gone.

  The door is its own listener on its own address with the key of this
  one relation, beside the Demiurge's own door. The thicket's mycelium
  and its operators' door stay exactly as they are without a parent.
  `:stop` there is `Leave`: the parent is asking a whole thicket to go.
  ```
  [relation]
  (def {:rpc url :psk psk} relation)
  (make-watch
    (fn [_ state _]
      (def own (get-in state [:rpc :functions] {}))
      (def functions
        (merge (select-keys own subthicket/door-operations)
               {:ping (fnr :ping [] :pong)
                :stop (fnr :stop [produce-resp ok-resp]
                           [(log "The parent asks the thicket to go") Leave])}))
      (^rpc url functions psk (. (state :name) " parent door") (state :debug) nil
            (make-watch [(^aether @{:op :ready}) (^supervisor/watch Leave)]
                        "ready for the parent")))
    "parent door"))

(defn demiurge/run
  "Runs the Demiurge lifecycle for a sequence of selected events."
  [initial-state events]
  (-> initial-state
      (make-manager on-error)
      (:transact ;events)
      :await))

(defn demiurge/serve
  ```
  Runs the serving Demiurge of a thicket.

  It is the only one serving its data: it holds `demiurge.lock` in its
  `:data-path` for as long as it runs, and a second one for the same
  thicket exits at once instead of supervising the same peers beside it.
  The kernel lets go of the claim however the holder ends.

  SIGTERM is `Leave`, so an init system stopping it, or a box shutting
  down, takes its peers down gracefully rather than orphaning them.

  Raised as a subthicket -- with the relation file named in its
  environment -- it also opens its parent's door, and writes what it
  prints to stderr, because its stdout is the parent's Aether. Without
  one it is exactly the Demiurge it has always been.
  ```
  [initial-state events]
  (supervisor/arm)
  (def dp (initial-state :data-path))
  (def [claimed claim]
    (if dp
      (protect (ownership/acquire (path/abspath (path/join dp "demiurge.lock"))))
      [true nil]))
  (unless claimed
    (eprint "Another Demiurge already serves " dp ": " claim)
    (os/exit 3))
  (defer (when claim (ownership/release claim))
    (def relation-file (os/getenv subthicket/variable))
    (def relation (when relation-file (parse (slurp relation-file))))
    (when relation (setdyn :out stderr))
    (def manager (make-manager initial-state on-error))
    (protect (os/sigaction :term (fn [&] (:transact manager Leave))))
    (:transact manager ;events ;(if relation [(^subthicket/door relation)] []))
    (:await manager)))

(defmacro demiurge/main
  ```
  Defines a Demiurge executable entry point with project-specific modes.

  Run with no arguments, it serves its thicket; see `demiurge/serve`.
  Every other mode -- bootstrap, test, builds -- runs as it always has.
  ```
  [initial-state & modes]
  ~(defn main
     "Main entry into Demiurge."
     [_ & mode]
     ((if (empty? mode) ,demiurge/serve ,demiurge/run)
       ,initial-state (match mode ,;modes))
     (,os/exit 0)))
