(import ./thicket :prefix "")
(import gp/tui)

# The symbiont's side: what a handle follows its view with.

(def- watch/lapse
  "Seconds a watch lives unawaited before the next watch takes it away."
  120)

(defn- watch/token []
  (string/join (map |(string/format "%02x" $) (os/cryptorand 8))))

(defn- ^watch/open
  "Subscribes a watch under `token` and lets watches long unawaited go."
  [view token chan topics]
  (make-update
    (fn [&]
      (def now (os/time))
      (def watches (or (view :handle/watches) (put view :handle/watches @{})))
      (eachp [t w] (table/clone (view :handle/watches))
        (when (< (w :seen) (- now watch/lapse))
          (eachp [_ chans] (get view :notify {})
            (while (def i (index-of (w :chan) chans)) (array/remove chans i)))
          (put watches t nil)))
      (each topic topics
        (update-in view [:notify topic] |(array/push (or $ @[]) chan)))
      (put (view :handle/watches) token
           @{:chan chan :topics topics :seen now}))
    "open handle watch"))

(defn- ^watch/close
  "Unsubscribes the watch under `token`."
  [view token]
  (make-update
    (fn [&]
      (when-let [w (get-in view [:handle/watches token])]
        (eachp [_ chans] (get view :notify {})
          (while (def i (index-of (w :chan) chans)) (array/remove chans i)))
        (put (view :handle/watches) token nil)))
    "close handle watch"))

(def membrane/funcs
  ```
  Membrane RPC functions by which a handle follows the view of the
  symbiont it reaches, for the symbiont to merge into its own.

  A watch is a subscription kept between calls, so nothing sent between
  one await and the next is lost: `:handle/watch` opens one on topics and
  names it, `:handle/await` waits on it at most the seconds given and
  returns the topics sent meanwhile (empty when none, `:stand-down` when
  the symbiont is leaving), `:handle/view` gives the values of keys of
  the view, and `:handle/unwatch` closes a watch. One unawaited for two
  minutes is closed by the next watch opened.
  ```
  @{:handle/watch
    (fn [_ topics]
      (def topics [;topics stage/stand-down])
      (def token (watch/token))
      (produce/applied [(^watch/open (dyn :view) token
                                     (ev/chan (inc (length topics))) topics)])
      token)
    :handle/await
    (fn [_ token secs]
      (def w (get-in (dyn :view) [:handle/watches token]))
      (assert w "unknown watch")
      (put w :seen (os/time))
      (def [ok taken]
        (protect (ev/with-deadline (min secs 60)
                   (notify/take (w :chan) (w :topics)))))
      (put w :seen (os/time))
      (cond
        (not ok) @[]
        (or (nil? taken) (= [stage/stand-down] taken)) :stand-down
        taken))
    :handle/view
    (fn [_ ks]
      (def view (dyn :view))
      (tabseq [k :in ks] k (get view k)))
    :handle/unwatch
    (fn [_ token]
      (produce/applied [(^watch/close (dyn :view) token)])
      :ok)})

# The handle's side.

(def- await/secs "Seconds one await waits on the symbiont." 25)

(defn connect
  ```
  Opens an RPC client to the symbiont the handle `config` reaches. A
  `timeout` other than the client's own lets a call wait that long.
  ```
  [config &opt timeout]
  (def client (rpc/client ;(server/host-port (config :rpc))
                          (config :name) (config :psk)))
  (if timeout (put client :timeout timeout))
  client)

(defn once
  ```
  Calls the method `cmd` names on the symbiont the handle `config`
  reaches, with `args`, and prints what it answers.
  ```
  [config &opt cmd & args]
  (unless cmd
    (eprint "usage: " (config :name) " method [args...]")
    (os/exit 2))
  (def client (connect config))
  (defer (:close client)
    (pp (apply (keyword cmd) client args))))

(defn- render [state]
  (def {:term term :app app :view view :editor ed} state)
  (def [rows cols] (tui/size))
  (def [live cursor] (tui/editor/render ed cols))
  (def blocks ((get app :render (fn [&] [])) view cols))
  (each b blocks
    (if (table? b) (put b :scroll (state :scroll))))
  (defn indented [line style]
    (cond
      (nil? line) ""
      (bytes? line) ["  " (tui/styled style line)]
      ["  " ;(if (indexed? line) line [line])]))
  (defn picked [piece]
    (tui/styled [:reverse :yellow :bold] (if (dictionary? piece) (piece :text) piece)))
  (defn lines-of [said style]
    (if (and (dictionary? said) (said :lines))
      (let [[r c] (if-let [i (state :choice)] (get-in said [:choices i :at]) [])]
        (seq [[i line] :pairs (said :lines)]
          (indented (if (= i r) (put (array ;line) c (picked (line c))) line)
                    style)))
      [(indented said style)]))
  (def laid
    (tui/stack
      rows
      live
      [;(lines-of (state :explanation) :dim)
       (if (state :online)
         (indented (state :message) :cyan)
         (indented (string "offline" (if-let [f (state :failure)] (string ": " f) ""))
                   :red))]
      (tui/rule cols)
      ;blocks))
  (put state :scroll (laid :scroll))
  (tui/present term (laid :lines) (if (state :input?) cursor)))

(def- Render (make-effect (fn [_ state _] (render state)) "handle render"))

(defn- drawn
  "The event of `update` named `name`, the screen drawn again after it."
  [update name]
  (make-event {:update update :effect (fn [_ state _] (render state))} name))

(defn- ^status [online &opt failure]
  (drawn
    (fn [_ state]
      (put state :online online)
      (put state :failure failure))
    "handle status"))

(defn- commands
  "The client commands go over, opened again when its line broke."
  [state]
  (def client (state :commands))
  (if (and client (client :stream))
    client
    ((put state :commands (connect (state :config))) :commands)))

(def- explain/quiet
  "Seconds typing stands still before the explanation is asked for."
  0.1)

(defn- ^explain
  ```
  Asks the app what the live line would do, once typing has stood still
  a moment, as the web console asks. An answer overtaken by later typing
  is let go.
  ```
  []
  (var n nil)
  (make-event
    {:update (fn [_ state]
               (set n (inc (get state :explain/n 0)))
               (put state :explain/n n))
     :watch
     (fn [_ state _]
       (when-let [explain (and (state :online) (get-in state [:app :explain]))]
         (producer
           (ev/sleep explain/quiet)
           (when (= n (state :explain/n))
             (def text (tui/editor/text (state :editor)))
             (def line
               (try (explain (commands state) (state :view) text)
                 ([err] (put state :commands nil) (tui/styled :red (string err)))))
             (if (= n (state :explain/n))
               (produce (drawn (fn [_ state]
                                 (put state :explanation line)
                                 (put state :explained text)
                                 (put state :choice nil))
                               "handle explanation")))))))}
    "handle explain"))

(defn- ^view [values]
  (make-event
    {:update (fn [_ state] (merge-into (state :view) values))
     # What the line would do depends on the view as well as on the line.
     :watch [(^explain)]
     :effect (fn [_ state _] (render state))}
    "handle view"))

(defn- ^message [message]
  (drawn
    (fn [_ state] (put state :message message))
    "handle message"))

(defn- follow
  ```
  A Producer that keeps the view of `state` as the symbiont has it: it
  fetches the view whenever the topics it watches are sent, and when the
  line breaks says so and connects again.
  ```
  [state]
  (def {:config config :app app} state)
  (def topics (get app :topics []))
  (def ks (get app :keys topics))
  (producer
    (forever
      (def client (connect config (+ await/secs 10)))
      (try
        (do
          (def token (:handle/watch client topics))
          (produce (^status true) (^view (:handle/view client ks)))
          (forever
            (def taken (:handle/await client token await/secs))
            (cond
              (= :stand-down taken) (error "the symbiont stood down")
              (present? taken) (produce (^view (:handle/view client ks))))))
        ([err] (produce (^status false (string err)))))
      (protect (:close client))
      (ev/sleep 2))))

(def- message/beat
  "Seconds each line of a message shows before the next one."
  1)

(defn- ^submit
  ```
  Submits `text` and shows the message it answers with. The lines of a
  message of more lines show one after another, the last one staying; a
  later message cuts them short.
  ```
  [text advance]
  (make-watch
    (fn [_ state _]
      (def {:app app :view view} state)
      (producer
        (def n (inc (get state :message/n 0)))
        (put state :message/n n)
        (def message
          (try ((app :submit) (commands state) view text advance)
            ([err] (put state :commands nil) (string "Error: " err))))
        (def said
          (cond
            (not (and (dictionary? message) (message :lines))) [message]
            (empty? (message :lines)) [nil]
            (message :lines)))
        (eachp [i line] said
          (if (pos? i) (ev/sleep message/beat))
          (if (= n (state :message/n)) (produce (^message line))))))
    "handle submit"))

(defn- quit [state]
  ((state :leave) (state :term) 0))

(defn- choices
  ```
  The choices the cloud of the explanation offers, when it explains the
  line as it stands.
  ```
  [state]
  (def said (state :explanation))
  (def offered (and (dictionary? said) (said :choices)))
  (if (and (present? offered)
           (= (state :explained) (tui/editor/text (state :editor))))
    offered))

(defn- ^key [k]
  (def key (k :key))
  (var submitted nil)
  (var changed false)
  (make-event
    {:update
     (fn [_ state]
       (def [rows cols] (tui/size))
       (def page (max 1 (- rows 10)))
       (def ed (state :editor))
       (def choice (state :choice))
       (cond
         (= key :ctrl-c) (quit state)
         (= key :wheel) (update state :scroll + (* 3 (k :dy)))
         (and (state :input?) (= key :tab))
         # Tab picks a button of the cloud, Tab again the next one and
         # Shift+Tab the one before; the line is left as it is.
         (when-let [offered (choices state)]
           (def n (length offered))
           (put state :choice
                (cond
                  choice (% (+ choice (if (k :shift) (dec n) 1)) n)
                  (k :shift) (dec n)
                  0)))
         (and choice (or (= key :enter) (= " " (k :text))))
         # Space or Enter takes the picked one into the line, as a click.
         (do
           (tui/editor/set ed (get-in state [:explanation :choices choice :text]))
           (put state :choice nil)
           (set changed true))
         (and choice (= key :esc)) (put state :choice nil)
         (state :input?)
         (do
           (put state :choice nil)
           (if (= key :esc)
             (put state :input? false)
             (case (tui/editor/key ed k cols)
               :submit (do (set submitted [(tui/editor/text ed) (truthy? (k :shift))])
                         (tui/editor/submit ed))
               :changed (set changed true))))
         (case [key (k :text)]
           [:char "q"] (quit state)
           [:char "i"] (put state :input? true)
           [:char "j"] (update state :scroll inc)
           [:char "k"] (update state :scroll dec)
           [:down nil] (update state :scroll inc)
           [:up nil] (update state :scroll dec)
           [:pgdn nil] (update state :scroll + page)
           [:pgup nil] (update state :scroll - page)
           [:home nil] (put state :scroll 0))))
     :watch (fn [&]
              (cond
                submitted [(^submit ;submitted) (^explain)]
                changed (^explain)))
     :effect (fn [_ state _] (render state))}
    "handle key"))

(defn session
  ```
  Runs the handle `config` as a live session in the terminal: the live
  line on top, what Ctrl+Enter would do under it, then what `app` draws
  of the symbiont's view, followed as it changes.

  `app` is a table of:
  * `:topics` -- the view topics to follow, `:keys` -- the view keys to
    fetch, the topics by default,
  * `:render` -- `(fn [view cols])` returning the blocks under the live
    line, as `tui/stack` takes them; a table among them scrolls,
  * `:explain` -- `(fn [client view text])` returning what submitting
    `text` would do, asked once typing stands still a moment,
  * `:submit` -- `(fn [client view text advance])` doing it over
    `client` and returning the message to show; `advance` when Shift was
    held. A message of more lines, `{:lines lines}`, shows them one after
    another, a second each.

  What `:explain` and `:submit` return is a line: a string, or pieces as
  gp/tui draws them. `:explain` can give more lines as `{:lines lines}`,
  and with them `:choices`, each `{:text text :at [row col]}`: the line
  `text` that the piece `col` of the line `row` leaves, as a button of
  the cloud does.

  Ctrl+Enter or Alt+Enter submits, Enter breaks the line. Tab picks one
  of the choices and Tab again the next, Space or Enter takes the picked
  one into the line, Esc lets it go. Esc leaves the line and `i` comes
  back. Outside it j/k, arrows, PgUp/PgDn and the wheel
  scroll, q quits; Ctrl+C quits anywhere.
  ```
  [config app]
  # What is said on stderr while the alternate screen is up would leave
  # with it, so it is kept and said once the terminal is given back.
  (def said @"")
  (def stderr* stderr)
  (defn leave [term code]
    (tui/close term)
    (file/write stderr* said)
    (file/flush stderr*)
    (os/exit code))
  (with-dyns [:err said]
    (def term (tui/open))
    (def state @{:config config :app app :term term :leave leave
                 :view @{} :online false :message nil
                 :editor (tui/make-editor {:prompt "> "})
                 :input? true :scroll 0})
    (defn on-error [_ err]
      (match err
        [kind event fiber]
        (do (eprintf "%s failed for %s with error: %s" kind
                     (get event :name) (fiber/last-value fiber))
          (debug/stacktrace fiber))
        (eprint err))
      (leave term 1))
    (def [ok res]
      (protect
        (-> (make-manager state on-error)
            (:transact Render
                       (make-watch (fn [&] (tui/key-producer term ^key)))
                       (make-watch (fn [&] (tui/ticker 1 (fn [] Render))))
                       (make-watch (fn [&] (follow state))))
            :await)))
    # Every producer of the session lives for ever, so one that returns
    # at all is a failure, said or not.
    (eprint "The session ended: " (if ok "its producers finished" res))
    (leave term 1)))

(defn run
  ```
  Runs the handle `config` with `app`, see `session`: with `args` once,
  by `:once` of `app` (`once` by default), and with none in a terminal as
  a live session.
  ```
  [config app args]
  (if (or (present? args) (not (tui/terminal?)) (nil? (app :submit)))
    (apply (get app :once once) config args)
    (session config app)))

(defmacro main
  "Defines a handle executable entry point around `run`."
  [config app]
  ~(defn main
     "Main entry into a handle executable."
     [_ & args]
     (,run ,config ,app args)
     (,os/exit 0)))
