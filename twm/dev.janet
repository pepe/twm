(import ./thicket :prefix "")

(defn demiurge/restart-watch
  "Runs Demiurge and restarts it when project source files change."
  [conf args]
  (def ch (ev/chan 9))
  (def fw (filewatch/new ch))
  (def mp (peg/compile ~{:matcher ,project-files-peg :main (<- :matcher)}))
  (def cmd |(os/spawn ["janet" "-d" "demiurge.janet" ;args] :p))
  (var demiurge (cmd))
  (ev/sleep 0.2)
  (def has-client? ((??? {first (?neq "test")}) args))
  (def autorun? (empty? args))
  (var client
    (if has-client?
      (rpc/client ;(server/host-port (conf :rpc))
                  :client (conf :psk))))
  (if autorun? (:run-peers client))
  (filewatch/add fw "./" :last-write :recursive)
  (filewatch/listen fw)
  (forever
    (def e (ev/take ch))
    (when-let [[fnm] (peg/match mp (e :file-name))]
      (eprinf "----------- File %s modified, restarting Demiurge" fnm)
      (if has-client? (:stop-peers client))
      (ev/sleep 0.1)
      (if has-client?
        (do
          (:stop client)
          (os/proc-wait demiurge))
        (os/proc-kill demiurge))
      (ev/sleep 0.2)
      (set demiurge (cmd))
      (ev/sleep 0.2)
      (if has-client?
        (set client
             (rpc/client ;(server/host-port (conf :rpc))
                         :client (conf :psk))))
      (if autorun? (:run-peers client)))))

(defn demiurge/test-once
  "Runs the root Demiurge test mode once."
  [args]
  (os/proc-wait
    (os/spawn ["janet" "-d" "demiurge.janet" "test" ;args] :p)))

(defn- test/project-change?
  [matcher event]
  (not (nil? (peg/match matcher (event :file-name)))))

(defn- test/read-result
  [exit-code aether]
  (match aether
    [true {:op :result :body result}] result
    [false err]
    (error (string "Demiurge test runner exited with " exit-code
                   " and sent an invalid Aether result: " err))
    _ (error (string "Demiurge test runner exited with " exit-code
                     " without a test result"))))

(defn- test/run
  [args]
  (def proc
    (os/spawn ["janet" "-d" "demiurge.janet" "test" ;args]
              :p {:out :pipe}))
  (def aether (protect (aether/read-message (proc :out))))
  (:close (proc :out))
  (def exit-code (os/proc-wait proc))
  (test/read-result exit-code aether))

(defn demiurge/test-watch
  "Runs the suite, waits on failures, and confirms focused fixes with the suite."
  [baseline]
  (def changes (ev/chan 64))
  (def watcher (filewatch/new changes))
  (def matcher
    (peg/compile ~{:matcher ,project-files-peg :main (<- :matcher)}))
  (filewatch/add watcher "./" :last-write :recursive)
  (filewatch/listen watcher)
  (def watch-state @{:dirty false})
  (ev/go
    (fn []
      (forever
        (def event (ev/take changes))
        (if (nil? event) (break))
        (when (test/project-change? matcher event)
          (put watch-state :dirty true)))))
  (var scope :full)
  (var files baseline)
  (defer (do
           (filewatch/unlisten watcher)
           (ev/chan-close changes))
    (forever
      (put watch-state :dirty false)
      (eprinf "----------- Running %s test suite"
              (if (= scope :full) "full" "focused"))
      (def result (test/run files))
      (def dirty? (watch-state :dirty))
      (def failing (result :failing))
      (if (empty? failing)
        (cond
          dirty?
          (do
            (eprint "----------- Source changed during the run; confirming the suite")
            (set scope :full)
            (set files baseline)
            (put watch-state :dirty false))

          (= scope :focused)
          (do
            (eprint "----------- Focused tests pass; confirming the full suite")
            (set scope :full)
            (set files baseline))

          (do
            (eprint "----------- All tests pass; waiting for a source change")
            (while (not (watch-state :dirty)) (ev/sleep 0.05))
            (ev/sleep 0.1)
            (put watch-state :dirty false)))
        (do
          (eprinf "----------- Waiting for a source change; failing tests: %s"
                  (string/join failing ", "))
          (while (not (watch-state :dirty)) (ev/sleep 0.05))
          (ev/sleep 0.1)
          (set scope :focused)
          (set files failing)
          (put watch-state :dirty false)))))
  0)

(defn demiurge/watch
  "Runs a one-shot test, supervised test watch, or the regular restart watcher."
  [conf args]
  (match args
    ["test/watch" & tests] (demiurge/test-watch tests)
    ["test" & tests] (demiurge/test-once tests)
    _ (demiurge/restart-watch conf args)))

(defmacro reimport
  "Freshly imports modules into the caller's scope."
  [& modules]
  ~(upscope
     ,;(map (fn [module]
              ~(import ,module :prefix "" :fresh true :export true))
            modules)))

(defmacro reload-store
  "Reloads a Store from the image named by a tree configuration file."
  [conf-file]
  ~(upscope
     (def tree
       (make Store
             :image ((parse (slurp ,conf-file)) :image)))
     (:init tree)))