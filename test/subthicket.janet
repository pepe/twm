(use spork/test)
(import ../twm/thicket :prefix "")
(import ../twm/demiurge :prefix "")
(import spork/path)
(import gp/net/rpc)

# A subthicket is a thicket's Demiurge supervised by another Demiurge. What
# matters is not what any one event does but what real processes do to one
# another -- which of them is raised where, who stops whom, and what is left
# running when one of them dies -- so these raise a real parent, a real
# child thicket and a real peer of the child, and look at them from outside.

(def root (path/abspath "test/_subthicket"))
(def twm-source (path/abspath "twm"))
(def psk/parent "parent-psk-parent-psk-parent-psk")
(def psk/child "child-psk-child-psk-child-psk-ch")
(def base (+ 21000 (* 10 (math/floor (* 300 (math/random))))))
(def ports {:parent (+ base 1) :child (+ base 2) :sleeper (+ base 3)
            :door (+ base 4)})
(defn at [k] (string "localhost:" (ports k)))

(defn rm-tree
  ```
  Removes `p` and all it holds. Windows refuses to delete a file for a
  moment after the process that held it has gone, so a refusal is tried
  again for a few seconds before it counts.
  ```
  [p]
  (when (os/stat p)
    (if (= :directory (os/stat p :mode))
      (do (each f (os/dir p) (rm-tree (path/join p f))) (os/rmdir p))
      (do
        (var tries 0)
        (while (not (first (protect (os/rm p))))
          (when (> (++ tries) 50) (os/rm p))
          (ev/sleep 0.1))))))

(defn import-line
  "An import of the twm module `module` from a file in `dir`."
  [dir module]
  (def rel (path/relpath dir (path/join twm-source module)))
  (string "(import " (string/replace-all "\\" "/" rel) " :prefix \"\")"))

(defn demiurge-script
  "A thicket's Demiurge, reading its whole configuration from CONF."
  [dir]
  (string
    (import-line dir "thicket") "\n"
    (import-line dir "navigation") "\n"
    (import-line dir "demiurge") "\n"
    (import-line dir "schema") "\n"
    "(def config (load-config))\n"
    "(spit \"pid\" (string (os/getpid)))\n"
    "(def initial-state\n"
    "  ((=<> (=>symbiont/initial-state :demiurge)\n"
    "        (>update :rpc (update-rpc rpc-funcs))\n"
    "        (>put :config config)\n"
    "        (>put :nav/symbiont =>symbiont/initial-state)) config))\n"
    "(demiurge/main initial-state [HeartCheck PrepareView RPC Ready])\n"))

(defn sleeper-script
  "A peer that does nothing but answer its mycelium."
  [dir]
  (string
    (import-line dir "thicket") "\n"
    (import-line dir "symbiont") "\n"
    "(def config (merge @{} (parse (slurp (os/getenv \"CONF\")))))\n"
    "(spit \"sleeper.pid\" (string (os/getpid)))\n"
    "(put config :rpc ((update-rpc @{}) (config :rpc)))\n"
    # Sandboxed by its own setup, as a peer granted only some :caps is:
    # what watches its supervisor must already be in place by then.
    "(def Sandbox (make-effect (fn [&] (sandbox :env :fs :threads :subprocess)) \"sandbox\"))\n"
    "(main config (^rpc/start AetherReady) Sandbox)\n"))

(def child-dir (path/join root "child"))
(def parent-dir (path/join root "parent"))

(def child-config
  {:name "child"
   :deploy {:host "localhost" :build-path child-dir
            :release-path (path/join child-dir "_release")
            :data-path (path/join child-dir "data")}
   :runtime {:debug false :log true}
   :mycelium {:psk psk/child
              :nodes {:demiurge {:rpc (at :child) :peers [:sleeper]}
                      :sleeper {:rpc (at :sleeper) :peers []}}}
   :membrane {:nodes {:demiurge {:rpc (at :child)}}}
   :symbionts {:demiurge {:entry "demiurge.janet" :builder false
                          :autostart [:sleeper] :builds [:sleeper]}
               :sleeper {:entry "sleeper.janet"}}})

(def parent-config
  {:name "parent"
   :deploy {:host "localhost" :build-path parent-dir
            :release-path (path/join parent-dir "_release")
            :data-path (path/join parent-dir "data")}
   :runtime {:debug false :log true}
   :mycelium {:psk psk/parent
              :nodes {:demiurge {:rpc (at :parent) :peers [:child]}
                      :child {:rpc (at :door)}}}
   :membrane {:nodes {:demiurge {:rpc (at :parent)}}}
   :symbionts {:demiurge {:entry "demiurge.janet" :builder false
                          :autostart [:child] :builds [:child]}
               :child {:entry "demiurge.janet" :shutdown 30
                       :subthicket {:build-path child-dir
                                    :log (path/join child-dir "data" "demiurge.log")}}}})

(defn lay-out []
  (rm-tree root)
  (each d [root child-dir parent-dir (path/join child-dir "data") (path/join parent-dir "data")]
    (os/mkdir d))
  (spit (path/join child-dir "demiurge.janet") (demiurge-script child-dir))
  (spit (path/join child-dir "sleeper.janet") (sleeper-script child-dir))
  (spit (path/join child-dir "conf.jdn") (string/format "%j" child-config))
  (spit (path/join parent-dir "demiurge.janet") (demiurge-script parent-dir))
  (spit (path/join parent-dir "conf.jdn") (string/format "%j" parent-config)))

(defn up?
  "Whether something accepts connections at `port`."
  [port]
  (def [ok conn] (protect (net/connect "localhost" port)))
  (when (and ok conn) (:close conn) true))

(defn eventually
  "Whether `f` holds within `seconds`, asked every tenth of a second."
  [f &opt seconds]
  (default seconds 20)
  # Measured on the clock: on Windows a refused localhost connection alone
  # takes seconds, so counting the sleeps would wait many times as long.
  (def deadline (+ (os/clock) seconds))
  (var held (truthy? (f)))
  (while (and (not held) (< (os/clock) deadline))
    (ev/sleep 0.1) (set held (truthy? (f))))
  held)

(defn call
  "Calls `method` at `port` with `psk`, or returns the failure."
  [port psk method & args]
  (def [ok answer]
    (protect
      (def c (rpc/client "localhost" (string port) "test" psk))
      (defer (:close c) (ev/with-deadline 5 (method c ;args)))))
  (if ok answer [:failed answer]))

(def logs
  "What each Demiurge raised by the test wrote to stderr, by its directory."
  @{})

(defn spawn-demiurge
  "Raises the Demiurge in `dir` the way a boot script or an operator would."
  [dir &opt env]
  (def environment (merge (os/environ)
                          {"CONF" (path/join dir "conf.jdn") :in :pipe :err :pipe}
                          (or env {})))
  (def janet (dyn *executable* "janet"))
  # Janet's :cd is not built for musl, as for the Demiurge itself.
  (def proc
    (if (= :windows (os/which))
      (os/spawn [janet "demiurge.janet"] :pe (put environment :cd dir))
      (os/spawn ["/bin/sh" "-c" `cd "$1" && shift && exec "$@"` "sh" dir janet "demiurge.janet"]
                :pe environment)))
  # Read into memory rather than into a file: Windows keeps a file handed
  # to a child open in this process, and the next suite could not remove it.
  (def log @"")
  (put logs dir log)
  (ev/spawn (while (:read (proc :err) 4096 log)))
  proc)

(defn pid-of [file] (when (os/stat file) (scan-number (string/trim (slurp file)))))

(defn kill [pid]
  (if (= :windows (os/which))
    (os/execute ["taskkill" "/F" "/PID" (string pid)] :p)
    (os/execute ["kill" "-9" (string pid)] :p)))

(defn all-down? []
  (not (some up? [(ports :parent) (ports :child) (ports :sleeper) (ports :door)])))

(defn alive?
  ```
  Whether the process `pid` still runs. Closed ports are not enough: a
  process can close every server it had and go on running, holding its
  store and its locks.
  ```
  [pid]
  (if (= :windows (os/which))
    (let [p (os/spawn ["tasklist" "/FI" (string "PID eq " pid) "/NH"] :p {:out :pipe})
          out (:read (p :out) :all)]
      (os/proc-wait p)
      (truthy? (string/find (string " " pid " ") (string out))))
    (zero? (os/execute ["sh" "-c" (string "kill -0 " pid " 2>/dev/null")] :p))))

(def quick
  ```
  Seconds a graceful departure of the whole herd may take. Shorter than the
  child's :shutdown, so a child the parent had to kill fails the test.
  ```
  20)

(defn herd
  "The pids of the running child and of its peer."
  []
  [(pid-of (path/join child-dir "pid")) (pid-of (path/join child-dir "sleeper.pid"))])

(defn gone?
  "Whether none of `pids` runs any more."
  [pids]
  (not (some alive? pids)))

(defn parent-log [] (string (get logs parent-dir "")))

(defn raise-herd
  "Raises the parent, asks it to run its peers, and waits for the child's peer."
  []
  (def parent (spawn-demiurge parent-dir))
  (assert (eventually |(up? (ports :parent))) "the parent rises")
  (call (ports :parent) psk/parent :run-peers)
  (assert (eventually |(up? (ports :door))) "the parent raises the child, which opens its parent's door")
  (def door-psk (subthicket/psk psk/parent :child))
  (call (ports :door) door-psk :run-peers)
  (assert (eventually |(up? (ports :sleeper))) "and the child, asked through that door, raises its own peer")
  parent)

(start-suite :scanner)
# A subthicket's stdout carries its Aether among whatever its builds write.
(let [[r w] (os/pipe)
      skipped @[]
      frame (aether/frame (marshal @{:op :ready}))
      scan (aether/scanner r |(array/push skipped $))]
  (:write w (string "generating executable c source build/x.c from x.janet...\n"
                    (string/slice frame 0 9)))
  (:write w (string (string/slice frame 9) "found native jhydro\nAETH02garbage"))
  (:write w frame)
  (:close w)
  (assert (deep= @{:op :ready} (scan)) "a frame is found among build output, even split across writes")
  (assert (deep= @{:op :ready} (scan)) "and a false start of a frame is stepped over")
  (assert (pos? (sum skipped)) "and what was stepped over is counted")
  (assert-error "the end of the stream is the end of the Aether" (scan)))
(end-suite)

(start-suite :policy)
(let [state @{:config parent-config :stop-timeout nil}]
  (assert (peer/subthicket state :child) "a subthicket is recognised by its :subthicket")
  (assert (nil? (peer/subthicket state :demiurge)))
  (assert (= 30 (peer/budget state :child)) "its own :shutdown is its budget")
  (assert (= 120 (peer/boot-window state :child)) "it is given longer to rise")
  (assert (not (peer/heartbeat? state :child)) "and missed heartbeats do not restart it")
  (assert (peer/heartbeat? @{:config child-config} :sleeper) "while they still restart an ordinary peer")
  (assert (= peer/patience (peer/budget @{:config child-config} :sleeper)))
  (assert (not= (subthicket/psk psk/parent :child) (subthicket/psk psk/parent :sibling))
          "every subthicket speaks with a key of its own"))
(end-suite)

(start-suite :standalone)
# Without a parent a thicket is exactly what it was: no door, no watching
# of a stdin that tells nothing, and alone on its data.
(lay-out)
(let [child (spawn-demiurge child-dir)]
  (:close (child :in))
  (assert (eventually |(up? (ports :child))) "a thicket rises by itself")
  (ev/sleep 1)
  (assert (up? (ports :child)) "and a stdin closed under it does not end it")
  (assert (not (up? (ports :door))) "and it opens no parent's door")
  (def second (spawn-demiurge child-dir))
  (assert (= 3 (os/proc-wait second)) "a second Demiurge for the same thicket refuses to serve")
  (assert (up? (ports :child)) "and leaves the first serving")
  (call (ports :child) psk/child :stop)
  (assert (= 0 (os/proc-wait child)) "and it stops as it always has"))
(end-suite)

(start-suite :nested)
(lay-out)
(def parent (raise-herd))
(def door-psk (subthicket/psk psk/parent :child))
(let [relation (parse (slurp (path/join parent-dir "data" "subthickets" "child.jdn")))]
  (assert (= (at :door) (relation :rpc)) "the child is told its parent's door")
  (assert (not= psk/parent (relation :psk)) "with its own key, not the parent's"))
(assert (match (call (ports :parent) psk/parent :state) [:running _ peers] (index-of :child peers))
        "the parent holds the child as a running peer")
(assert (match (call (ports :child) psk/child :state) [:bootstrapped] true [:running _ _] true)
        "the child keeps its own door for its own operators, with its own key")
(assert (= :pong (call (ports :door) door-psk :ping)) "the parent's door answers the parent's key for the child")
(assert (match (call (ports :door) (subthicket/psk psk/parent :sibling) :ping) [:failed _] true)
        "and refuses a sibling's")
(assert (match (call (ports :door) psk/child :ping) [:failed _] true)
        "and the child's own key")
(assert (string/find "Starting" (slurp (path/join child-dir "data" "demiurge.log")))
        "the child writes its log to its own file, not to its parent's Aether")
(def pids (herd))
(call (ports :parent) psk/parent :stop)
(assert (eventually |(gone? pids) quick)
        "stopping the parent ends the child, and the child its peer -- the processes, not only their doors")
(assert (= 0 (os/proc-wait parent)) "and the parent exits cleanly")
(assert (all-down?))
(assert (not (string/find "did not exit" (parent-log)))
        "nobody had to be killed on the way")
(assert (string/find "child generation 1 exited: 0" (parent-log))
        "the child left by itself")
(end-suite)

(start-suite :parent-killed)
(lay-out)
(def parent (raise-herd))
(def pids (herd))
(kill (pid-of (path/join parent-dir "pid")))
(os/proc-wait parent)
(assert (eventually |(gone? pids) quick)
        "when the parent is killed, the child leaves, and takes its own peer with it")
(assert (all-down?))
(end-suite)

(start-suite :child-killed)
(lay-out)
(def parent (raise-herd))
(def [first-child first-sleeper] (herd))
(kill first-child)
(assert (eventually |(not (alive? first-sleeper)) quick)
        "a killed child's peer notices and leaves instead of staying behind")
(assert (eventually |(and (up? (ports :door)) (not= first-child (pid-of (path/join child-dir "pid")))) 60)
        "and the parent raises a new child in its place")
(def second-child (first (herd)))
(call (ports :parent) psk/parent :stop)
(assert (eventually |(gone? [second-child]) quick) "and stops it as gracefully as the first")
(os/proc-wait parent)
(assert (not (string/find "did not exit" (parent-log))) "without killing it")
(end-suite)

(unless (= :windows (os/which))
  (start-suite :sigterm)
  (lay-out)
  (def parent (raise-herd))
  (def pids (herd))
  (os/proc-kill parent false :term)
  (assert (eventually |(gone? pids) quick) "SIGTERM stops the whole herd gracefully")
  (assert (= 0 (os/proc-wait parent)) "and the parent exits as asked, not killed")
  (assert (not (string/find "did not exit" (parent-log))) "with nobody killed on the way")
  (end-suite))

(rm-tree root)
