(import gp/atomic)
(import spork/path)
(import spork/sh)
(import jhydro :prefix "")

(defn digest
  "Content identity (Hydrogen hash, 256 bits), independent of filenames and time."
  [bytes]
  (string (util/bin2hex (hash/hash 32 bytes "TWMbuild"))))

(defn fingerprint
  "Stable configuration identity without publishing configuration or credentials."
  [value]
  (defn canonical [x]
    (cond
      (dictionary? x) [:map ;(map |[$ (canonical (x $))] (sort-by string (keys x)))]
      (indexed? x) [:sequence ;(map canonical x)]
      x))
  (digest (string/format "%j" (canonical value))))

(defn source
  "Records the Git revision and the actual non-ignored source contents, including edits."
  [root]
  (ev/with-deadline 30
    (def revision (sh/exec-slurp "git" "-C" root "rev-parse" "HEAD"))
    (def names (filter |(not (empty? $))
                      (string/split "\0" (sh/exec-slurp "git" "-C" root "ls-files"
                                                       "-z" "--cached" "--others" "--exclude-standard"))))
    {:revision revision
     :dirty (not (empty? (sh/exec-slurp "git" "-C" root "status" "--porcelain")))
     :digest (fingerprint
               (map (fn [name]
                      (def file (path/join root name))
                      [name (when (= :file (os/stat file :mode)) (digest (slurp file)))])
                    (sorted names)))}))

(defn- directory-files [root &opt prefix]
  (default prefix "")
  (def found @[])
  (each name (sorted (os/dir (path/join root prefix)))
    (def relative (path/join prefix name))
    (def file (path/join root relative))
    (case (os/lstat file :mode)
      :directory (array/concat found (directory-files root relative))
      :file (array/push found [relative (digest (slurp file))])))
  found)

(defn dependency
  "Identifies the installed dependency bytes actually used by a build, not a guessed commit."
  [module]
  (def [file kind] (module/find module))
  (assert file (string "Cannot identify build dependency " module))
  {:digest (fingerprint (directory-files (path/dirname file)))})

(defn provenance
  "Captures source, installed GP/TWM dependencies, runtime and configuration identities."
  [root config]
  {:source (source root)
   :dependencies {:gp (dependency "gp/events") :twm (dependency "twm/app")}
   :janet {:version janet/version :build janet/build
           :platform (os/which) :architecture (os/arch)}
   :configuration (fingerprint config)})

(defn read-installed
  "Verifies a sidecar against the executable; stale or absent metadata is explicitly unverified."
  [executable]
  (if-not (os/stat executable)
    {:status :absent}
    (let [actual (digest (slurp executable))
          sidecar (string executable ".provenance.jdn")
          [ok metadata] (protect (parse (slurp sidecar)))]
      (if (and ok (dictionary? metadata) (= actual (metadata :artifact)))
        (merge metadata {:status :verified})
        {:status :unverified :artifact actual}))))

(defn record
  "Records provenance for a completed build, bound to its exact executable bytes."
  [executable provenance]
  (def metadata (merge provenance {:artifact (digest (slurp executable)) :built-at (os/time)}))
  (atomic/write (string executable ".provenance.jdn") (string/format "%j" metadata))
  metadata)

(defn install
  "Atomically installs a verified executable, then its digest-bound provenance."
  [built destination]
  (def metadata (read-installed built))
  (assert (= :verified (metadata :status)) "Build provenance is missing or does not match its artifact")
  (atomic/copy built destination 8r700)
  (atomic/write (string destination ".provenance.jdn")
                (slurp (string built ".provenance.jdn")))
  metadata)
