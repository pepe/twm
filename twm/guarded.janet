# A guarded symbiont holds its door only while it is used. The demiurge
# pings it on every beat, and the answer says when it was last used; once
# that is further back than the demiurge's `:timeout`, the demiurge calls
# `:stop` on it. What the symbiont owes that contract is here: counting its
# use, reporting it, and leaving well when it is stopped -- telling whoever
# is watching, and giving the door back to its guardian.
(import ./thicket :prefix "")
(import ./sentry
        :only [session/check-with session/publish StandDown]
        :prefix "")

(defn ^activity
  ```
  Event that marks the symbiont as used at `ts`.

  It is kept in the view, where the ping reads it. A symbiont puts it there
  as it stands up, too: standing up is use, and the idle clock starts then,
  not at a first request that may never come.
  ```
  [ts]
  (make-update
    (fn [_ {:view view}] (put view :last-active ts))
    "activity"))

(defn session/checker-with
  ```
  Creates middleware admitting a request with a valid session and counting
  it as activity. A request without one is answered with `not-auth`, as
  `session/check-with` answers it.

  The demiurge stops a guarded symbiont left idle for longer than its
  `:timeout`, going by the `:last-active` its ping reports. Every request
  that touches data comes through here, so this is where use is counted --
  and only once the session is found. Counting a refused request would let
  anyone keep an unattended symbiont standing, and nobody could then sign
  in past it.

  A stream the browser opens by itself is admitted with `session/check-with`
  instead, and not counted. The browser opens it again whenever it is cut
  -- by a proxy's read timeout, by the network -- and a reopening nobody
  asked for is not use: counted, it would keep an unattended symbiont
  standing for as long as its tab stayed open.
  ```
  [not-auth]
  (def admitted (session/check-with not-auth))
  (fn [next-middleware]
    (admitted
      (fn counted [req]
        (produce (^activity (os/time)))
        (next-middleware req)))))

(defh /watching
  ```
  Answers a tab reporting that it is being looked at again, and counts it
  as activity.

  Reading a page makes no requests, so a page read for a quarter of an hour
  looks exactly like one left unattended, and would be stopped. The page
  says it is being looked at by asking for this; when it asks is its own
  affair.

  It stands behind the session check like every other route of a guarded
  symbiont, and must: counting a refused request would let anyone keep an
  unattended symbiont standing. Behind `session/check-with`, that is, so it
  is counted once rather than twice. The check is not made here because a
  project may put all its routes behind one of its own, and the cookies can
  be read only once: `http/cookies` puts what it parsed in place of the
  header, and a second one raises on it.

  The empty stream is there because Datastar asked and is owed something it
  can parse.
  ```
  []
  (produce (^activity (os/time)))
  (http/stream))

(defr -:ping/active
  ```
  RPC function that answers the demiurge's ping with when the symbiont was
  last used, as `[:last-active epoch]`.

  The demiurge stops it once that is further back than its `:timeout`. An
  answer carrying no time is counted as a missed beat, and three of those
  restart the symbiont, which is why it marks itself used as it stands up.
  ```
  []
  (define :view)
  [:last-active (view :last-active)])

(def stand-down/patience
  ```
  Seconds a stopped symbiont gives its live streams to say it is leaving
  before it stands down regardless.

  Saying so is one write per stream, made by a fiber in this very process,
  so a stream that has not finished within a second has lost its reader.
  Short, too, because the demiurge waits only `peer/patience` after asking a
  peer to stop and then ends it, and a peer ended that way has neither
  given its door up nor said so.
  ```
  1)

(defn ^stand-down/after-stage
  ```
  Waits for live streams to finish their leaving, within
  `stand-down/patience`, and stands down.

  Each stream writes its leaving from its own fiber once `stage/stand-down`
  reaches it, and standing down ends the process those fibers write from.
  Standing down at once would cut the leaving off, and the page would be
  left showing a place that has gone.
  ```
  []
  (make-watch
    (fn [_ {:view view} _]
      (producer
        # A stream unsubscribes once it has said its leaving.
        (protect (ev/with-deadline stand-down/patience
                   (until (empty? (get-in view [:notify stage/stand-down] []))
                     (ev/sleep 0.005))))
        (produce StandDown)))
    "stand down after stage responses"))

(defn stop/guarded
  ```
  Creates the RPC function the demiurge calls as `:stop` on a guarded
  symbiont: when it has been idle longer than the demiurge's `:timeout`, or
  when the thicket is released.

  Such a stop is asked for by nobody. A logout is answered with its own
  transition; here the streams would simply die under a page still showing
  a place that has gone. So whoever is watching is told first:
  `stage/stand-down` goes to every live stream, which says it is leaving
  and sends the page back to the door. Then the symbiont stands down as a
  logout does, giving the door up and saying so, rather than merely dying
  -- its guardian is told by the leaving instead of by the death.

  Without `end-session` the session outlives the symbiont, and the guardian
  waiting at the door offers the way back in. With it the session ends too,
  so the door asks for the secret again rather than letting an unattended
  browser back in. Standing down does not wait on the ending: a release
  stops the tree beside this symbiont, and one that could not end its
  session must still leave rather than be killed.
  ```
  [&named end-session]
  (fnr :stop/guarded [produce-resp ok-resp]
       (define :view)
       # Not every view carries a name -- some are built from a handful of
       # selected keys. The bare fallback should read as the omission it is.
       [(log (get view :name "a guarded symbiont") "'s RPC server stops")
        (^notify/send stage/stand-down)
        ;(if end-session
           [(^session/cap false)
            (make-watch
              (producer
                (protect (session/publish ""))
                (produce (^stand-down/after-stage)))
              "end session and stand down")]
           [(^stand-down/after-stage)])]))

(def +:stop/guarded
  "RPC function stopping a guarded symbiont whose session outlives it, see `stop/guarded`."
  (stop/guarded))
