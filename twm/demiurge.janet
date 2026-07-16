(import ./thicket :prefix "")
(use spork/sh-dsl spork/sh
     spork/declare-cc spork/cc spork/build-rules)

(setdyn *rpc-defines* [:view])

(defn peer/spit-conf
  "Spits the config for the `peer`"
  [state peer &opt nav]
  (default nav (state :nav/symbiont))
  (let [conf (jdn/render ((nav peer) (state :config)))
        file (. "conf." (peer/file-name peer) ".jdn")]
    (spit file conf)
    file))

(defn peer/pipe-out
  "Spawns the process with pipe out"
  [state peer cmd flags]
  (def fs (keyword flags :e))
  (def env
    (merge (os/environ)
           {"CONF" (peer/spit-conf state peer)
            :out :pipe}))
  (os/spawn cmd fs env))

(defn ^save-sha
  "Event that saves git sha"
  [sha]
  (make-update
    (fn [_ {:view view}]
      ((>put :sha sha) view))
    "save sha"))

(define-event SetReleasedSHA
  "Writes the current SHA to file"
  {:update
   (fn [_ {:view view}] (put view :release-sha (view :sha)))
   :effect
   (fn [_ {:view {:sha sha} :release-path rp} _]
     (if sha (spit (path/abspath (path/join rp "release.sha")) sha)))})

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
  "Removes peer from spawned"
  [peer]
  (make-update
    (fn [_ state]
      (def {:view {:spawned spawned}} state)
      (when (spawned peer)
        (put spawned peer nil)
        (def ep (state peer))
        (if (dictionary? ep)
          (put state peer (string (ep :host) ":" (ep :port))))))
    (. "remove peer " peer)))

(defn ^peer/stop
  "Stops one peer"
  [peer]
  (make-event
    {:watch (^peer/remove peer)
     :effect
     (fn [_ state _]
       (def pc (state peer))
       (protect (:stop pc)
                (:close pc)))}
    (. "stop peer " peer)))

(define-event StopPeers
  "Sends stop RPC to all peers"
  {:update (fn [_ {:view view}] (put view :ran false))
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
  "Saves spawned peer process"
  [peer phase]
  (make-event
    {:update
     (fn [_ {:view {:spawned spawned}}]
       (put spawned peer phase))
     :watch (log peer " reached " phase)}
    (. "save spawned peer " peer)))

(defn ^peer/connect
  "Connects to one peer"
  [peer &opt succ]
  (make-event
    {:update
     (fn [_ state]
       (def {:psk psk :name name} state)
       (def url (state peer))
       (when (string? url)
         (def [host port] (server/host-port url))
         (put state peer
              (make rpc/Client
                    :host host :port port
                    :psk psk :name name))))
     :watch
     (fn [_ state _]
       (producer
         (def {:name name} state)
         (var failed false)
         (var tries 0)
         (if-not (state :ping)
           (while
             (match [(protect (:open (state peer))) tries]
               [[true _] _] (produce (log name " connected to " peer))
               [[false _] 10] (produce (log name " cannot connect to " peer "."))
               true)
             (ev/sleep (* (++ tries) 0.1))))
         (if succ (produce succ))))}
    (. "connect peer " peer)))

(defn ^peer/run
  "Runs one peer and manages its process lifecycle in one threaded producer"
  [group &opt peer cmd flags]
  (make-watch
    (fn [_ state _]
      (def {:entries entries} state)
      (producer
        (default peer group)
        (def [_ _ [ecmd eflags]] (entries peer))
        (default cmd ecmd)
        (default flags eflags)
        (def ae @"")
        (let [proc (peer/pipe-out state peer cmd flags)]
          (produce (^peer/save-spawned group :boot))
          (ev/read (proc :out) 1 ae)
          (when (= (. ae) "1")
            (produce
              (^peer/connect group
                             (^peer/save-spawned group :mycelium))))
          (buffer/clear ae)
          (def exit-code (os/proc-wait proc))
          (produce
            (if (zero? exit-code)
              (log (or peer group) " exited with success")
              (log (or peer group) " exited with code " exit-code)))
          (ev/read (proc :out) 128 ae) # aether has limit
          (produce (^peer/remove group)))
        (if-not (empty? ae)
          (let [[p next-arg] (unmarshal (string/replace-all "\r" "" ae))
                [_ _ [cmd flags]] (entries p)]
            (produce (log group " occupation continues with " p))
            (produce (^peer/run group p [;cmd next-arg] flags))))))
    (. "run peer " peer)))

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

(defn ^peer/ping
  "Pings one peer and updates its missed heartbeat count."
  [peer]
  (make-watch
    (fn [_ state _]
      (try
        (match (:ping (state peer))
          :pong
          [(^peer/clear peer) (^peer/no-active peer)]
          [:last-active (dt (epoch? dt))]
          [(^peer/active peer dt) (^peer/clear peer)]
          [(^peer/mark peer)])
        ([e] [(^peer/mark peer)])))
    (. "ping peer " peer)))

(define-watch PingPeers
  "Pings all spawned peers and records heartbeat failures."
  [_ {:view {:spawned peers}} _]
  (seq [[peer phase] :pairs peers
        :when (= phase :mycelium)]
    (^peer/ping peer)))

(define-watch CheckPeers
  "Restarts peers that missed three consecutive heartbeats."
  [_ {:view view :timeout timeout} _]
  (def c @[])
  ((=>
     (<- c (=<> :misses pairs (>Y (=<> 1 (?gt 2)))
                (>map (=<> 0 |[(^peer/clear $) (^peer/no-active $)
                               (^peer/stop $) (^peer/run $)]))))
     (<- c (=<> :activity pairs (>Y (=<> last |(- (os/time) $) (?gt timeout)))
                (>map (=<> 0 |[(^peer/clear $) (^peer/no-active $)
                               (^peer/stop $)]))))
     (>base c) flatten)
    view))

(defn ^peer/deploy
  "Deploys one peer"
  [peer]
  (make-event
    {:watch (log "Deployed peer " peer)
     :effect
     (fn [_ {:build-path bp :release-path rp} _]
       (def pf (peer/file-name peer))
       (def bexep (executable (path/join bp "_build/develop" pf)))
       (def exep (executable (path/join rp pf)))
       (sh/copy-file bexep exep)
       (os/chmod (path/abspath exep) 8r700))}))

(define-watch Deploy
  "Deploys peers"
  [_ {:entries entries} _]
  (seq [peer :keys entries] (^peer/deploy peer)))

(defn ^peer/build
  "Builds one `peer`"
  [peer]
  (make-effect
    (fn [_ state _]
      (def {:entries entries :name name} state)
      (def [e exep _] (entries peer))
      (def rules @{})
      (with-dyns [*rules* rules
                  *build-root* "_build"]
        (os/setenv "CONF" (peer/spit-conf state peer))
        (declare-project :name (. name "-" peer))
        (declare-executable :entry e :name (. (peer/file-name peer)))
        (build-run rules "build")
        (os/setenv "CONF" nil)))))

(define-watch Build
  "Builds peers"
  [_ {:entries entries} _]
  (seq [p :keys entries] (^peer/build p)))

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

(defn ^release
  "Event that releases the new version of the thicket."
  [now]
  (make-watch
    (fn [_ {:dry dry :builder builder :view {:ran ran}} _]
      [(^mark-release now)
       ;[;(if (or (not builder) dry)
            [(log "Build dry run") StopPeers]
            [CleanBuild Build StopPeers Deploy])
         SetReleasedSHA Released Ready
         (if ran RunPeers Empty)]
       (log "Release finished")])
    "release"))

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
                 {:view @{:spawned @{} :misses @{} :activity @{}}
                  :entries tentries}))
   :effect (fn [_ {:view view :build-path bp} _]
             (os/cd bp)
             (setdyn :view view))})

(defn guard-releasing
  "Guards the rpc runction for the release"
  [handler]
  (fn [& args]
    (define :view)
    (if-let [from (view :releasing)]
      [:busy from (view :sha)]
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
  "RPC function, that code versions "
  []
  [:versions (view :sha) (view :release-sha)])

(defr +:release
  "RPC function, that starts the release if possible."
  [guard-releasing]
  (let [now (os/clock)]
    (produce (^release now))
    [:ok now]))

(defr +:stop-peers
  "RPC function, that stops the peers if possible."
  [guard-releasing]
  (if (view :ran)
    (do (produce StopPeers) :ok)
    :not-running))

(defr +:run-peers
  "RPC function, that starts the peers if possible."
  [guard-releasing]
  (if-let [ran (view :ran)]
    [:running ran]
    (do
      (produce RunPeers)
      :ok)))

(defr +:restart-peers
  "RPC function, that starts the peers if possible."
  [produce-resp ok-resp guard-releasing]
  [StopPeers RunPeers])

(defr +:stop
  "RPC function that stops the demiurge."
  [produce-resp ok-resp guard-releasing]
  [(^delay 0.001 Stop)])

(defr +:pull
  "RPC function that stops the demiurge."
  [produce-resp ok-resp guard-releasing]
  [PullGetSHA])

(def rpc-funcs
  "RPC functions"
  @{:state -:state
    :release +:release
    :run-peers +:run-peers
    :stop-peers +:stop-peers
    :restart-peers +:restart-peers
    :pull +:pull
    :versions -:versions
    :stop +:stop})

(defn ^bootstrap-arg
  "Saves the bootstrap argument"
  [arg]
  (make-update
    (fn [_ state] (put state :bootstrap (keyword arg)))))

(def HeartCheck
  "Heart beat checker function"
  (heart-beat
    [PingPeers CheckPeers]
    (fn :ping [i {:view {:spawned spawned :releasing releasing}}]
      (and (not releasing) (present? spawned) (= 0 (mod i 2))))))

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
  "Runs one file test and report"
  [path &opt done]
  (make-watch
    (fn [&]
      (def pass
        (zero? (os/execute [(dyn *executable* "janet") "--" path] :p)))
      (if done (ev/give done path))
      [(^inc :total) (if pass (^inc :passed) (^failed path))])))

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
  "Runs the test"
  [& files]
  (make-watch
    (fn [&]
      (producer
        (let [done (ev/chan)]
          (produce (logr "\e[2J\e[H\e[30;103m---------- Running Tests ----------\e[0m")
                   ClearTests)
          (loop [f :in files
                 :let [path (string "test/" f)]
                 :when (string/has-suffix? ".janet" path)]
            (produce ClearData (^peer/run :tree) (^peer/connect :tree))
            (ev/sleep 0.2)
            (produce (logr "\n----- In file " path " -----") (^test/file path done))
            (ev/take done)
            (ev/sleep 0.2)
            (produce (^peer/stop :tree))))
        (produce TestReport)))))

(defn ^download
  "Downloads the remote data-path to `dest`"
  [dest]
  (make-effect
    (fn [_ {:host host :data-path dp :name name} _]
      (os/execute ["scp" "-r" (. host ":" dp "/*") dest] :p))
    (. "download to " dest)))
