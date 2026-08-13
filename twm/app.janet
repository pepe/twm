(import ./base :prefix "" :export true)
(import gp/net/uri :export true)

(def . "string" string)

(def Empty
  "Empty event"
  (make Event))

# HTTP utils
(defdyn *handler-defines* "Dynamics that should be defined in the handler")
(defdyn *heart-tick* "Rate for the `heart-beat` producer")

(defn handler-fn
  ```
  Constructs anonymous handler function, which is used by
  `defh` and `fnh` macros.
  The function implicitly defines the request `req` and derivate values:
  `headers`, `body`, `params` and `query-params`.
  It also defines dynamics as set by `*handler-defines*`.
  ```
  [name body]
  ~(fn ,name [req]
     (def {:headers headers :body body :method method :uri uri
           :params params :query-params query-params} req)
     ,;(seq [defne :in (dyn *handler-defines* [])]
         ~(def ,(symbol defne) (dyn ,defne)))
     ,;body))

(defmacro defh
  "Defines handler function with with features from `handler-fn`."
  [name docstr middlewares & body]
  ~(def ,name ,docstr
     ,(if (empty? middlewares)
        (handler-fn name body)
        ~(->
           ,(handler-fn name body)
           ,;middlewares))))

(defmacro fnh
  "Defines anonymous handler function with features from `handler-fn`."
  [name middlewares & body]
  (if (empty? middlewares)
    (handler-fn name body)
    ~(->
       ,(handler-fn name body)
       ,;middlewares)))

(defn membrane/resp
  ```
  A Membrane response: HTML that must never be answered from cache.

  The Membrane is the one document a posture change does not renew, which
  is exactly what lets it survive the change -- and it is also why nothing
  ever displaces a copy the browser has kept. A Membrane cached while the
  guardian held the door outlives the handover: it goes on showing the
  stage the guardian last patched, and asks nothing of whoever holds the
  place now, because from the browser's side no navigation is due. A
  reload does not help, since the cached document is what is revalidated.

  `/content` is already safe -- the SSE head says `no-cache` -- so it is
  only the document wrapping it that can go stale. `no-store` keeps it as
  short-lived as the posture it was served in.

  The headers table is made fresh on every call: `html-success-resp`
  merges the content type into whatever it is given.
  ```
  [body]
  (http/html-success-resp body @{"Cache-Control" "no-store"}))

# RPC
(defdyn *rpc-defines* "Dynamics with what should defined in rpc-fn")

(defn rpc-fn
  ```Constructs anonymous RPC handler function, used by defr and fnr.
The function implicitly defines the rpc argument rpc and binds
dynamics as set by *rpc-defines*.```
  [name body]
  (with-syms [args]
    ~(fn ,name [& ,args]
       (def [rpc & args] ,args)
       ,;(seq [defne :in (dyn *rpc-defines* [])]
           ~(def ,(symbol defne) (dyn ,defne)))
       ,;body)))

(defmacro defr
  "Defines RPC function with features from `rpc-fn`."
  [name docstr middlewares & body]
  ~(def ,name ,docstr
     ,(if (empty? middlewares)
        (rpc-fn name body)
        ~(->
           ,(rpc-fn name body)
           ,;middlewares))))

(defmacro fnr
  "Defines anonymous RPC function with features from `rpc-fn`."
  [name middlewares & body]
  (if (empty? middlewares)
    (rpc-fn name body)
    ~(->
       ,(rpc-fn name body)
       ,;middlewares)))

# Events
(define-update Clean
  "Marks store as clean"
  [_ state]
  (put state :dirty false))

(define-event Flush
  "Flushes the store"
  {:watch (fn [&] [(log "Flushing store") Clean])
   :effect (fn [_ {:store store} _]
             (:flush store)
             (gccollect))})

(defn heart-beat
  ```
  Periodic heart beat event. `event-pairs` should be in fromat
  `events` `predicate`. Produces `events` if the `predicate` is truthy
  for the `heart` counter and the manager's `state`.

  Tick duration could be set by the `*heart-tick*` dynamic and
  defaults to 1 second.
  ```
  [& event-pairs]
  (assert (even? (length event-pairs)))
  (def rules (partition 2 event-pairs))
  (make-watch
    (fn [_ state _]
      (producer
        (def tick (dyn *heart-tick* 1))
        (var heart tick)
        (forever
          (each [events pred] rules
            (if (pred heart state) (produce ;events)))
          (ev/sleep tick)
          (++ heart))))
    "heart-beat"))

(define-event PrepareStore
  "Prepares store in the state."
  {:update (fn [_ state] (put state :store (make Store :image (state :image))))
   :watch (fn [_ {:image image} _]
            (log "Initializing store image named " image))
   :effect (fn [_ {:store s} _] (:init s) (gcsetinterval 0x7FFFFFFF))})

(define-event SeedStore
  "Seeds the empty store from the `:seed` file."
  {:update (fn [_ state]
             (def {:store store :seed seed} state)
             (when (and seed (empty? (:transact store keys)))
               (:save store (parse (slurp seed)))
               (put state :seeded true)))
   :watch (fn [_ {:seed seed :seeded seeded} _]
            (if seeded (log "Seeding store from " seed)))
   :effect (fn [_ {:store store :seeded seeded} _]
             (if seeded (:flush store)))})

(define-watch Stop
  "Stop the server, flush store and exits"
  [&]
  (producer
    (ev/sleep 0.001)
    (exit)))

(defn space/dwell
  ```
  Gives the current fiber an environment of its own, layered over the one
  it inherited, and binds `view` in it.

  A producer is a `coro`, and a `coro` inherits its parent's environment
  by reference: a plain `setdyn` inside one reaches every sibling producer
  and the parent besides. Layering keeps a space's view to itself, while
  everything else the fiber inherited still resolves through the
  prototype, and every connection the server accepts inherits it in turn.
  ```
  [view]
  (when view
    (def fiber (fiber/current))
    (fiber/setenv fiber (table/setproto @{:view view} (fiber/getenv fiber)))))

(defn spaces
  ```
  The living spaces a symbiont raises.

  A symbiont always raises its own, described by the state itself, and
  then one for every place it stands in for another. A space describes
  itself with the same keys the state would: `:http`, `:rpc`, `:routes`,
  `:public`, `:static`, `:name`, `:log` and `:view`, and carries only the
  addresses it actually answers on — a guardian's own space is mycelium
  alone, and `HTTP` and `RPC` each take the spaces that concern them.
  ```
  [state]
  (if-let [inhabited (state :spaces)]
    [state ;(values inhabited)]
    [state]))

(def- space/holding
  ```
  What every living space currently holds, keyed by the space itself.

  Listeners, the fibers accepting on them and their channels are live
  machinery, and a symbiont's state is marshalled whole whenever it hands
  work to a thread. A fiber blocked in `net/accept` cannot cross that
  boundary at all, so what a space holds is kept beside the state instead
  of in it.
  ```
  @{})

(defn space/held
  "The addresses `space` currently holds, keyed by kind."
  [space]
  (or (space/holding space)
      (let [held @{}] (put space/holding space held) held)))

(defn space/listen
  ```
  Opens one of `space`'s addresses, of `kind`, on `url`, feeding `chan`.

  What it takes is kept on the space: the listener to close, the fiber
  accepting on it to cancel, and the channel and address to open it again.
  A space is every address it answers on, so giving one up means giving
  up all of them, and a symbiont that kept only its membrane would go on
  holding the mycelium address the rising symbiont needs.
  ```
  [space kind chan url]
  (def [_ listener] (server/start chan ;(server/host-port url)))
  (put (space/held space) kind
       @{:listener listener :chan chan :url url})
  space)

(defn space/let-go
  ```
  Closes every address `space` holds, at once and here rather than as an
  event.

  A handler that hands its place over answers the request that asked for
  it, and that answer sends the asker straight back to the door. Letting
  go as an event leaves the door open across the reply, and the asker can
  return through it before the guardian has stepped aside. Established
  connections outlive their listener, so the reply still arrives.
  ```
  [space]
  (each held (values (space/held space))
    (when-let [listener (held :listener)]
      (protect (:close listener)))
    (put held :listener nil))
  space)

(defn ^space/vacate
  ```
  Event giving up every address of one living `space`, without disturbing
  the other spaces or the symbiont that holds them.

  Only the listeners go. The supervisors stay parked on their channels and
  the symbiont keeps its peers, its registration and its session, so the
  place can be taken back with `^space/resume` and nothing has to be
  introduced to the thicket a second time.
  ```
  [space]
  (make-effect (fn [&] (space/let-go space)) (. "vacate " (space :name))))

(defn ^space/resume
  "Event taking back every address of one living `space`."
  [space]
  (make-effect
    (fn [&]
      (each [kind held] (pairs (space/held space))
        (unless (held :listener)
          (space/listen space kind (held :chan) (held :url)))))
    (. "resume " (space :name))))

(defn ^space/http
  ```
  Producer running the HTTP server of one living `space`.

  The space's view is bound inside the producer rather than around it,
  because a dynamic binding belongs to the fiber that makes it and is
  inherited by every connection the server accepts. That is what lets
  one symbiont hold several spaces without their views meeting.
  ```
  [space]
  (def {:http http :log log? :name name :view view
        :routes routes :public public :static static} space)
  (assert http "HTTP host and port must be set, exiting.")
  (assert (table? routes) "Routes must be table, exiting.")
  (if static (assert public "Public path must be set, exiting."))
  (def parser
    (http/parser
      (cond-> routes
              # The space's own `:not-found` answers whatever is not a file,
              # so a Membrane kept in that slot survives the static handler
              # being put there. A space without one gets gp's plain 404.
              static (put :not-found
                          (http/static public nil (routes :not-found)))
              true http/drive log? (event-journal name))))
  (make-watch
    (producer
      (space/dwell view)
      (def chan (ev/chan 128))
      (space/listen space :http chan http)
      (produce (logf "Starting %s HTTP server on %s, port %s" name ;(server/host-port http)))
      (http/supervisor
        chan
        (http/on-connection parser)
        [:product events] (produce ;events)
        [:error fiber]
        # A fiber can fail with no connection to answer on: the accepting
        # fiber does exactly that when the space is vacated. Only a failure
        # that has someone waiting on it is worth a reply.
        (if-let [conn (get (fiber/getenv fiber) :conn)]
          (do
            (def err (fiber/last-value fiber))
            (eprint name " HTTP Supervisor: " err)
            (when (dyn :debug) (debug/stacktrace fiber))
            (protect
              (:write conn
                      (http/internal-server-error
                        (string "Internal Server Error: " err))))
            # Neither the answer nor the closing is allowed to raise. A
            # vacated space hands its accepting fiber's failure here, and
            # what that fiber inherited under :conn is a connection that
            # has already been answered and closed, if it is one at all.
            (protect (:close conn)))
          (when (dyn :debug)
            (eprint name " HTTP Supervisor: " (fiber/last-value fiber))))))
    (. "http " http)))

(define-watch HTTP
  "Creates a producer with a running HTTP server for every living space."
  [_ state _]
  (setdyn :debug (state :debug))
  (seq [space :in (spaces state) :when (space :http)] (^space/http space)))

(defn ^delay
  "Delay the `event` for `s` time"
  [s event]
  (make-watch (producer (ev/sleep s) (produce event)) "delay"))

(define-watch Exit
  "Logs exiting and stops"
  [_ {:name name} _] [(log name " is exiting.") Stop])

(def aether/magic
  "Wire prefix for version-two Aether frames."
  "AETH02")

(def aether/max-size
  "Largest accepted Aether payload in bytes."
  (* 64 1024))

(defn aether/hex
  ```
  The bytes of `payload` spelled out in hexadecimal.

  A marshalled payload carries whatever bytes it pleases, newlines among
  them, and the Aether travels over stdout, which is a text stream: every
  newline written to it on Windows arrives as two bytes. The frame is then
  longer than its length declares and the reader begins the next frame in
  the middle of this one. Hex has no newline to translate.

  Nothing showed while a guardian wrote one frame and died, because there
  was no next frame to begin in the wrong place.
  ```
  [payload]
  (string/join (map |(string/format "%02x" $) payload)))

(defn aether/unhex
  "The bytes that `hex` spells out."
  [hex]
  (def bytes @"")
  (loop [i :range [0 (length hex) 2]]
    (buffer/push-byte bytes
                      (scan-number (string "0x" (string/slice hex i (+ i 2))))))
  bytes)

(defn aether/frame
  "Frames an Aether payload with its versioned prefix and fixed-width length."
  [payload]
  (def hex (aether/hex payload))
  (string aether/magic (string/format "%012d" (length hex)) hex))

(defn- aether/read-exact
  [stream n]
  (def bytes @"")
  (while (< (length bytes) n)
    (def chunk (:read stream (- n (length bytes))))
    (when (or (nil? chunk) (empty? chunk))
      (error "Aether stream ended before the framed message was complete"))
    (buffer/push-string bytes chunk))
  bytes)

(defn aether/read
  "Reads one version-one framed Aether payload from `stream`."
  [stream]
  (assert (= aether/magic (string (aether/read-exact stream (length aether/magic))))
          "Invalid Aether frame prefix")
  (def size (scan-number (string (aether/read-exact stream 12))))
  (assert (and size (<= 0 size aether/max-size))
          "Invalid Aether message length")
  (aether/unhex (string (aether/read-exact stream size))))

(def aether/operations
  "Version-one Aether operation vocabulary; only ready, spawn, left, and result are live today."
  [:ready :spawn :left :build :deploy :release :result])

(defn aether/message?
  "Whether `message` is one of the narrow version-one Aether envelopes."
  [message]
  (and (dictionary? message)
       (keyword? (message :op))
       (index-of (message :op) aether/operations)))

(defn aether/read-message
  "Reads and validates one marshalled Aether envelope from `stream`."
  [stream]
  (def message (unmarshal (aether/read stream)))
  (assert (aether/message? message)
          (string/format "Invalid Aether message: %p" message))
  message)

(defn ^aether
  "Writes one framed Aether envelope to stdout."
  [message]
  (assert (aether/message? message) "Invalid Aether message")
  (make-effect
    (fn [&]
      (:write stdout (aether/frame (marshal message)))
      (:flush stdout))
    "write to aether"))

(defn ^aether/spawn
  "Requests the permitted birth of `peer`, optionally carrying its argument."
  [peer arg]
  (^aether @{:op :spawn :peer peer :arg arg}))

(defn ^aether/left
  ```
  Says that `place` has been let go of and is free for its guardian.

  Announced rather than asked, and only ever after the addresses are
  actually closed: it is a report of something already done, so whoever
  acts on it cannot arrive too early. A place nobody guards is announced
  all the same and simply interests no one.
  ```
  [place]
  (^aether @{:op :left :place place}))

(defn ok-resp
  "RPC MW that returns :ok after the body"
  [handler]
  (fn [& args]
    (handler ;args)
    :ok))

(defn produce-resp
  "RPC MW that produces the response of the handler"
  [handler]
  (fn [& args]
    (produce ;(handler ;args))))

(defn ^rpc
  ```
  Constructs producer with running rpc server.

  Given the living `space` it answers for, it dwells in that space's view
  and hands it the address to hold, so the space can be given up whole.
  ```
  [url functions psk name deb &opt space after-start]
  (assert (present-string? url) "RPC host and port must be set, exiting.")
  (assert (present-string? psk) "RPC psk must be set, exiting.")
  (default functions {})
  (default after-start Empty)
  (assert (dictionary? functions) "RPC functions must be dictionary, exiting.")
  (make-watch
    (producer
      (setdyn :debug deb)
      (when space (space/dwell (space :view)))
      (let [[host port] (server/host-port url)
            chan (ev/chan 128)]
        (if space
          (space/listen space :rpc chan url)
          (server/start chan host port))
        (produce (logf "Starting %s RPC on %s, port %s" name
                       ;(server/host-port url))
                 after-start)
        (rpc/supervisor
          chan
          (rpc/on-connection
            (merge-into @{:psk psk} functions))
          # rpc/supervisor puts its own [:error fiber] rule ahead of these,
          # so a rule for it here would never be reached.
          [:product events] (produce ;events))))
    (. "rpc " url)))

(defn ^space/rpc
  "Event running the mycelium server of one living `space`."
  [space psk deb &opt after-start]
  (def {:rpc {:url url :functions functions} :name name} space)
  (def fns
    (merge
      {:stop
       (fnr :stop [produce-resp ok-resp]
            [(log name " RPC server going down")
             Stop])
       :ping (fnr :ping [] :pong)}
      functions))
  (^rpc url fns psk name deb space after-start))

(defn ^rpc/start
  "Starts every RPC listener and produces `succ` only after all bind."
  [succ &opt fail]
  (default fail Exit)
  (make-event
    {:watch
     (fn [_ state _]
       (def {:psk psk :debug deb} state)
       (def servers
         (seq [space :in (spaces state) :when (space :rpc)] space))
       (producer
         (var pending (length servers))
         (def bound
           (make-effect
             (fn [&]
               (-- pending))
             "RPC bound"))
         (if (zero? pending)
           (produce ;(if (indexed? succ) succ [succ]))
           (do
             (produce ;(map |(^space/rpc $ psk deb bound) servers))
             (var waited 0)
             (while (and (pos? pending) (< waited 500))
               (ev/sleep 0.01)
               (++ waited))
             (if (zero? pending)
               (produce ;(if (indexed? succ) succ [succ]))
               (produce fail))))))}
    "start RPC"))

(define-watch RPC
  "Creates a producer with a running RPC server for every living space."
  [_ state _]
  (def {:psk psk :debug deb} state)
  (seq [space :in (spaces state) :when (space :rpc)] (^space/rpc space psk deb)))

(defn on-error
  "Manages errors for events' manager. Transacts detail logging."
  [manager err]
  (:transact
    manager
    ;(match err
       (msg (string? msg)) (log msg)
       ([at event f] (keyword? at) (valid? event) (fiber? f))
       (cond-> @[(logr (string at " failed for " (event :name)
                               " with error: " (fiber/last-value f)))]
               (dyn :debug) (array/push (stacktrace f)))
       (error "Unexpected error type"))))

# Test helpers

(def success?
  "HTTP success validator"
  (??? {:status (?eq 200)}))

(def not-found?
  "HTTP success validator"
  (??? {:status (?eq 404)}))

(defn success-has?
  "HTTP success with `parts` validator"
  [& parts]
  (??? {:status (?eq 200)
        :body (?find ;parts)}))

(defn success-has-not?
  "HTTP success without `part` validator"
  [& parts]
  (??? {:status (?eq 200)
        :body (complement (?find ;parts))}))

(defn redirect?
  "HTTP redirect to `location` validator"
  [location]
  (??? {:status (?eq 303)
        :headers (??? {"content-length" (?eq "0")
                       "location" (?eq location)})}))

# Misc
(defn make-send-email
  "Constructs function that sends emails with cli curl"
  [url me pwd]
  (fn :make-send-email
    [to file]
    (def [email] (peg/match '(* (thru "<") '(to ">")) me))
    (os/execute
      ["curl" "--ssl-reqd" "--url" url "--user" (string email ":" pwd)
       "--mail-from" email "--mail-rcpt" to "--upload-file" file] :px
      {:out (sh/devnull)})))

(defn timestamp
  "Timestamps entity `o`"
  [o]
  (put o :timestamp (os/time)))

(defn pipe-out
  "Spawns the process with pipe out"
  [[cmd flags]]
  (os/spawn cmd flags {:out :pipe}))

(defn hash
  "Returns hash item"
  [item]
  (and
    item
    (string (util/bin2hex (hash/hash 16 item (dyn :ctx))))))

(defn peer/file-name
  "File name for the peer"
  [peer]
  (string/replace-all "/" "__" peer))

(defn human
  "Capitalizes and replace -"
  [name]
  (string/join
    (->> name (string/split "-")
         (map |(string (string/ascii-upper
                         (string/from-bytes ($ 0))) (slice $ 1 -1))))
    " "))

(define-watch Ready
  "Event that logs readiness"
  [_ {:name name} _]
  (log (human name) " is ready"))

(define-watch AetherReady
  "Logs readiness and announces it to the supervising Demiurge."
  [_ _ _]
  [Ready (^aether @{:op :ready})])

(def project-files-peg
  "PEG for filewatch"
  '(+
     (* (thru ".janet") -1)
     (* "templates" (thru ".temple") -1)))

(defn chunk-msg
  "Contructs chunk from msg"
  [msg]
  (string/format "%x\r\n%s\r\n" (length msg) msg))

(defn ds/msg/patch-elements
  ```
  One SSE message patching `elements`, as a string rather than a write.

  A message that is a value can be composed into a document ahead of time;
  one that writes itself can only ever be performed. Transitions are built
  from these.
  ```
  [elements &opt selector mode]
  (chunk-msg
    (string
      "event: datastar-patch-elements\n"
      (if selector (string "data: selector " selector "\n"))
      (if mode (string "data: mode " mode "\n"))
      # One `data:` line per line of markup. A field in an event stream
      # ends at the newline, so elements carrying one -- a stylesheet, a
      # script, anything preformatted -- would end the field early and
      # leave the rest of themselves as stray lines. Datastar reads what it
      # was given, which is a truncated element and some nonsense, and the
      # selector it was told to replace is emptied rather than replaced.
      (string/join
        (map |(string "data: elements " $)
             (string/split "\n" (string elements)))
        "\n")
      "\n\n")))

(defn ds/patch-elements
  "Writes patch-elements SSE message to conn"
  [elements &opt selector mode]
  (protect
    (:write (dyn :sse-conn)
            (ds/msg/patch-elements elements selector mode))))

(defn ds/hg/patch
  "patch-elements from hg `elements`"
  [elements &opt selector mode]
  (ds/patch-elements (hg/html elements) selector mode))

(defn ds/msg/patch-signals
  ```
  One SSE message patching `signals`, as a string rather than a write.

  A message that is a value can be composed into a document ahead of time;
  one that writes itself can only ever be performed. Transitions are built
  from these.
  ```
  [signals]
  (chunk-msg
    (string
      "event: datastar-patch-signals\n"
      "data: signals " (json/encode signals) "\n\n")))

(defn ds/patch-signals
  "Writes patch-elements SSE message to conn"
  [signals]
  (protect (:write (dyn :sse-conn) (ds/msg/patch-signals signals))))

(defn ds/msg/remove-elements
  ```
  One SSE message removing every element matching `selector`, as a string
  rather than a write.

  Removing an element is also how its listening stops: a stream opened by
  `data-init` belongs to the element carrying it, and an element that has
  left the document is not waiting for anything. There is no separate way
  to say "stop listening", and wanting one is how a transition acquires
  client-side logic.
  ```
  [selector]
  (chunk-msg
    (string
      "event: datastar-patch-elements\n"
      "data: mode remove\n"
      "data: selector " selector "\n\n")))

(defn ds/msg/beat
  ```
  One SSE message patching in the element that waits `delay` and then opens
  `path` again.

  This is the whole of a transition's waiting and reopening, and it is
  written down rather than performed. Datastar's streams are fetches, not
  `EventSource`s, so a stream the server closes stays closed and nothing
  reconnects on its own -- which is what makes the reopening sayable in the
  document instead of guessed at by whoever closes it.

  `data-init` takes a `delay` modifier, so the beat is an attribute and not
  a script; nothing here runs but Datastar.
  ```
  [selector path &opt wait]
  (default wait "500ms")
  (ds/msg/patch-elements
    (string "<div id=\"beat\" data-init__delay." wait "=\""
            "@get('" path "')\"></div>")
    selector "append"))

(defn ds/transition
  ```
  A whole Living Place transition, as one static string of SSE messages.

  A posture change is the same five things every time: the elements whose
  streams must stop, the elements that no longer belong, a beat, the close,
  and the reopening. Only the first two differ between going in and coming
  out, so the transition is worth saying once and keeping.

  Built from its parts and held in a `def`, a transition is a constant in
  the image before any request arrives. Nothing about it is decided while
  someone is waiting: the document is the same string for every visitor,
  and the only thing a handler chooses is which of the two to write.

  `beat` is how long the waiting lasts. `gone` are the selectors to remove -- listeners and stale elements alike,
  since removal is the only way either ends. `into` is where the beat is
  appended and `path` what it reopens; closing the stream is the handler's
  last act and needs nothing said here.

  `signals` are set first, before anything is taken away, and they are the
  other half of removing an element: a signal outlives the element that
  declared it, so a posture change that takes away a form and says nothing
  about what the form collected leaves it in the document -- and in the
  query string of every request the document makes afterwards.

  `saying` is written where the beat waits, after what is going has gone.
  A handover takes about a second, and for that second the place had
  nothing in it: the gate was already removed and whoever is rising had
  not yet been asked for anything. An empty stage is indistinguishable
  from a broken one.
  ```
  [&named gone into path beat signals saying]
  (default into "body")
  (default path "/content")
  (string
    (if signals (ds/msg/patch-signals signals) "")
    ;(map ds/msg/remove-elements (or gone []))
    (if saying (ds/msg/patch-elements (hg/html saying) into "inner") "")
    (ds/msg/beat into path beat)))

(defn ds/get
  "Constructs ds get uri"
  [& parts]
  (string "@get('" ;parts "')"))

(defn ds/post
  "Constructs ds post uri"
  [& parts]
  (string "@post('" ;parts "')"))

(defn ds/hg-stream #TODO rename
  "Convenience for defining SSE stream handler"
  [elements]
  (http/stream
    (each [element selector mode] elements
      (ds/patch-elements (hg/html element) selector mode))))

(defn ds/input
  "Datastar input helper"
  [name & attrs]
  [:input (struct ;attrs :data-bind name)])

(defn ds/select
  "Datastar select helper"
  [name options]
  [:select {:data-bind name} options])

(defn ds/query
  "Convenience that parses query params datastar data"
  [next-middleware]
  (fn [req]
    (next-middleware
      ((http/query-params
         (fn [req]
           (def c @[])
           ((=>
              (<- c
                  (=> :query-params "datastar"
                      (>if present?
                           (=> json/decode (>map-keys keyword)
                               (>map-vals (=> (>if string? |(string/replace-all "+" " " $))))))))
              |(put $ :datastar (array/pop c))) req))) req))))

(defn shlc
  "Joins `parts` and make sh -lc"
  [& parts]
  [:sh "-lc" (string/join parts " ")])

(defn jdn/render
  "Renders Janet `item` into jdn"
  [item]
  (string/format "%j" item))

(defmacro defargs
  "Convenience for defining arguments"
  [binding]
  ~(def ,binding args))

(def- digits
  ["zero" "one" "two" "three" "four" "five" "six"
   "seven" "eight" "nine" "ten"])

(defn digit->word
  "Map from digit to word"
  [digit]
  (get digits digit))

(defn word->digit
  "Map from word to digit"
  [word]
  (find-index (?eq word) digits))

(defn update-rpc
  "Prepares RPC configuration"
  [funcs]
  (fn [url] @{:url url :functions funcs}))

(defn >stamp
  "Function that timestamps"
  [x]
  ((>put :timestamp (os/time)) x))

(defn derive-from
  "Derives new key from master `key`"
  [key]
  (setdyn :ctx "intrstdy")
  (->> key
       (kdf/derive-from-key 16 (os/time) (dyn :ctx))
       util/bin2hex
       freeze))

(defn <script/redirect/>
  ```
  hg representation of the redirect script.

  It knocks before it goes. A handover closes the door before it answers,
  so until the rising symbiont binds there is nobody behind the address at
  all, and a browser sent there in that gap meets a refusal rather than a
  wait wherever a closed port is answered honestly. Waiting a fixed
  moment instead only moves the guess: a symbiont is usually ready in a
  tenth of a second and has been seen to take four.

  The handover page waits one second for the receiving symbiont to take its
  door, then enters it. There is no browser-side polling here.
  ```
  [&opt address]
  (default address "/")
  [:script
   (hg/raw
     (. ``var mtbDoor = "`` address ``";
          function mtbEnter() {
            setTimeout(function () { document.location = mtbDoor; }, 1000);
          }
          mtbEnter();``))])

(defn sanitize-nl
  "Replaces \n for <br>"
  [s]
  (string/replace-all "\n" "<br>" s))

(defn ^notify/subscribe
  "Subscribes a channel for a notification topic."
  [chan topic]
  (make-update
    (def-state _
      (=> :view :notify topic (>add chan)))
    (. "subscribe notify " topic)))

(defn ^notify/send-one
  "Sends one topic notification to a subscribed channel."
  [chan topic]
  (make-effect
    (fn [&]
      (:give chan topic))
    (. "send one notify " topic)))

(defn ^notify/clear
  "Clears all subscriptions for a notification topic."
  [topic]
  (make-update
    (fn [_ {:view {:notify {topic chans}}}]
      (array/clear chans))
    (. "clear notify " topic)))

(defn ^notify/send
  "Sends a topic to all subscribers and clears the subscription queue."
  [topic]
  (make-watch
    (fn [_ {:view {:notify notify}} _]
      (if-let [chans (notify topic)]
        [;(seq [chan :in chans]
            (^notify/send-one chan topic))
         (^notify/clear topic)]
        []))
    (. "send notify " topic)))

(defn produce/wait
  ```
  Subscribes `chan`, produces `event`, waits for `topic`, and returns `result`.
  ```
  [chan topic event result]
  (produce (^notify/subscribe chan topic) event)
  (ev/take chan)
  result)
