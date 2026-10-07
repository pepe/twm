(use spork/test)
(import ../twm/thicket :prefix "")
(import ../twm/guarded :prefix "")
(import ../twm/sentry :as sentry)
(import ../twm/demiurge :as demiurge)

# A guarded symbiont and the demiurge share one contract: the ping says when
# the symbiont was last used, and a symbiont idle for longer than the
# demiurge's :timeout is asked to stop. These hold both sides to it, and
# hold the symbiont to leaving well. Nothing here transacts `StandDown`,
# which would exit the test: events are read as the manager would be given
# them.

(defn supervise
  ```
  Runs `f` as the manager runs a producer, and returns the events it
  produces, in order, once it and every producer it starts have ended.
  ```
  [f]
  (def chan (ev/chan 16))
  (def events @[])
  (var running 1)
  (ev/go f nil chan)
  (while (pos? running)
    (match (ev/take chan)
      [:product produced] (array/concat events produced)
      [:producer fiber] (do (++ running) (ev/go fiber nil chan))
      [:ok _] (-- running)
      [_ fiber] (propagate (fiber/last-value fiber) fiber)))
  events)

(defn names
  "Names of `events`."
  [events]
  (map |($ :name) events))

(defn named
  "The one of `events` called `name`."
  [events name]
  (find |(= name ($ :name)) events))

(defn as-symbiont
  "Runs `f` with `view` as the view, and returns its answer and what it produced."
  [view f]
  (def answer @[])
  (def events (supervise (fn [] (setdyn :view view) (array/push answer (f)))))
  [(first answer) events])

(defn long-ago [] (- (os/time) 600))

(start-suite :reporting-use)
(let [state @{:view @{}}]
  (:transact (make-manager state) (^activity 1234))
  (assert (= 1234 (get-in state [:view :last-active]))
          "use is kept in the view, where the ping reads it"))

(let [[answer] (as-symbiont @{:last-active 1234} |(-:ping/active nil))]
  (assert (deep= [:last-active 1234] answer)
          "the ping says when the symbiont was last used"))

(defn demiurge/pinging
  "A demiurge state whose only peer, pepe, answers its ping as a symbiont with `view`."
  [view]
  @{:pepe @{:ping (fn [_] (with-dyns [:view view] (-:ping/active nil)))}
    :timeout 60
    :view @{:spawned @{:pepe :mycelium} :misses @{} :activity @{}
            :lifetimes @{}}})

# The demiurge's side: what the ping answers is what it decides by.
(let [used (long-ago)
      state (demiurge/pinging @{:last-active used})
      manager (make-manager state)]
  (:transact manager (demiurge/^peer/ping :pepe))
  (:await manager)
  (assert (= used (get-in state [:view :activity :pepe]))
          "the demiurge keeps the time the ping answers with")
  (assert (zero? (get-in state [:view :misses :pepe]))
          "and counts the beat as answered")
  (assert (index-of "stop peer pepe"
                    (names ((demiurge/CheckPeers :watch) nil state nil)))
          "a symbiont idle longer than the timeout is asked to stop"))

(let [state (demiurge/pinging @{:last-active (os/time)})
      manager (make-manager state)]
  (:transact manager (demiurge/^peer/ping :pepe))
  (:await manager)
  (assert (not (index-of "stop peer pepe"
                         (names ((demiurge/CheckPeers :watch) nil state nil)))))
          "one used within it is left standing")

# Standing up has to count as use, or the first answer carries no time.
(let [state (demiurge/pinging @{})
      manager (make-manager state)]
  (:transact manager (demiurge/^peer/ping :pepe))
  (:await manager)
  (assert (= 1 (get-in state [:view :misses :pepe]))
          "an answer without a time is a missed beat"))
(end-suite)

(start-suite :counting-use)
(def session (sentry/=>session/?eq "abcd"))
# Made afresh for every call: reading the cookies rewrites the request.
(defn signed-in [] @{:headers @{"Cookie" "session=abcd"}})
(defn stranger [] @{:headers @{"Cookie" "session=nope"}})
(def counted? |(index-of "activity" (names $)))

(def checked ((session/checker-with "not yours") (fn [_] :passed)))
(let [[answer events] (as-symbiont @{:cap/session session} |(checked (signed-in)))]
  (assert (= :passed answer) "a request with the session is admitted")
  (assert (counted? events) "and counted as use"))
(let [[answer events] (as-symbiont @{:cap/session session} |(checked (stranger)))]
  (assert (string/find "not yours" answer) "one without it is refused with the page given")
  (assert (not (counted? events)) "and a refusal is not use"))

# Mounted as a guarded symbiont mounts it, behind the session check.
(def watching ((sentry/session/check-with "not yours") /watching))
(let [[answer events] (as-symbiont @{:cap/session session} |(watching (signed-in)))]
  (assert (function? answer) "a tab looked at again is answered with a stream")
  (assert (= 1 (count |(= "activity" $) (names events)))
          "and counted as use, once"))
(let [[answer events] (as-symbiont @{:cap/session session} |(watching (stranger)))]
  (assert (string/find "not yours" answer) "a tab without the session is refused")
  (assert (not (counted? events))
          "so nobody without one keeps the symbiont standing"))
# A project may check every route with a check of its own, which has read
# the cookies by the time the request arrives.
(let [read @{:headers @{"Cookie" @{"session" "abcd"}}}
      [answer events] (as-symbiont @{:cap/session session} |(/watching read))]
  (assert (function? answer) "watching leaves the cookies to the check")
  (assert (counted? events)))
(end-suite)

(start-suite :leaving)
(defn stopping
  "Calls the `stop` RPC function on a symbiont with `view`, returning its answer and events."
  [stop view]
  (as-symbiont view |(stop nil)))

(let [view @{:name "pepe"}
      sub (subscription/open view [:todos stage/stand-down] stage/stand-down)
      [answer events] (stopping +:stop/guarded view)
      said (names events)]
  (assert (= :ok answer) "the demiurge is answered")
  (assert (< (index-of "send notify stage/stand-down" said)
             (index-of "stand down after stage responses" said))
          "whoever is watching is told before the symbiont stands down")
  (assert (not (index-of "save session" said)) "the session outlives it")
  (:transact (make-manager @{:view view})
             (named events "send notify stage/stand-down"))
  (assert (= stage/stand-down (subscription/take sub))
          "and a live stream hears it")
  (subscription/close sub))

(let [view @{:name "pepe" :cap/session session}
      [answer events] (stopping (stop/guarded :end-session true) view)
      said (names events)]
  (assert (= :ok answer))
  (assert (< (index-of "send notify stage/stand-down" said)
             (index-of "save session" said)
             (index-of "end session and stand down" said))
          "ending the session closes the door here before telling the tree")
  (assert (not (index-of "stand down after stage responses" said))
          "standing down waits for the ending to be tried")
  (:transact (make-manager @{:view view}) (named events "save session"))
  (assert (false? (view :cap/session)) "nobody is let in on the old session"))

(let [[_ events] (stopping +:stop/guarded @{})]
  (assert (named events "stand down after stage responses")
          "a view without a name stops all the same"))

(defn standing-down
  "Stands down from `view`, returning the events and the seconds it took."
  [view]
  (def started (os/clock))
  (def events
    (supervise (((^stand-down/after-stage) :watch) nil @{:view view} nil)))
  [events (- (os/clock) started)])

# Timers fire up to a tick early -- ten milliseconds or so on Windows -- so
# a wait is held to what it was meant to be within this much.
(def slack 0.05)

(let [view @{}
      sub (subscription/open view [stage/stand-down] stage/stand-down)]
  (ev/spawn (ev/sleep 0.2) (subscription/close sub))
  (def [events took] (standing-down view))
  (assert (deep= @["StandDown"] (names events)) "it stands down")
  (assert (< (- 0.2 slack) took (- stand-down/patience slack))
          "once its live streams have finished their leaving"))

(let [view @{}
      sub (subscription/open view [stage/stand-down] stage/stand-down)]
  (def [events took] (standing-down view))
  (assert (deep= @["StandDown"] (names events)))
  (assert (< (- stand-down/patience slack) took (+ stand-down/patience 0.5))
          "and a stream that never finishes holds it up no longer than its patience")
  (subscription/close sub))

(let [[events took] (standing-down @{})]
  (assert (deep= @["StandDown"] (names events)))
  (assert (< took 0.1) "with nobody watching it stands down at once"))
(end-suite)
