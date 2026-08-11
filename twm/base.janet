(import spork/misc :prefix "" :export true)
(import spork/json :export true)
(import spork/netrepl :export true)
(import spork/temple :export true)
(import spork/htmlgen :as hg :export true)
(import spork/path :export true)
(import spork/mdz :export true)
(import spork/sh :export true)
(import jhydro :prefix "" :export true)

(import gp/route :export true)
(import gp/utils :prefix "" :export true)
(import gp/data :prefix "" :export true)
(import gp/events :prefix "" :export true)
(import gp/datetime :as dt :export true)
(import gp/net/server :export true)
(import gp/net/http :export true)
(import gp/net/rpc :export true)
(import gp/data/fuzzy :export true)

(defn log :shadow
  "Create logging event from the message `msg`."
  [& msg]
  (make-effect
    (fn log [_ state _]
      (when (state :log)
        (let [now (os/clock)
              t (math/floor now)
              p (string (mod now 1))]
          (eprin (dt/format-date-time t) "." (slice p 2 7) " - ")
          (eprint ;msg))) "log")))

(defn diag
  "Create a redacted diagnostic logging event.

  Diagnostic output follows the normal log switch so it is available in a
  deployed instance without changing the event machinery.  It is deliberately
  prefixed, making the temporary trace easy to filter or remove later."
  [& msg]
  (make-effect
    (fn diagnostic [_ state _]
      (when (state :diagnostic)
        (let [now (os/clock)
              t (math/floor now)
              p (string (mod now 1))]
          (eprin (dt/format-date-time t) "." (slice p 2 7) " - DIAG ")
          (eprint ;msg))) "diagnostic")))

(defn logr
  "Create logging event from the message `msg`."
  [& msg]
  (make-effect (fn log [_ state _]
                 (if (state :debug) (eprint ;msg))) "log"))

(defn logf
  "Create logging formating event from the `format` and the message `msg`."
  [format & msg]
  (log (string/format format ;msg)))

(defn event-journal
  ```
  Middleware that produces log of the request, naming the living space it
  was asked of.

  A peer's stderr is the Demiurge's own, so one file carries the whole
  thicket; and one symbiont holds as many living spaces as it stands in
  doors, answering all of them from a single process. Unnamed, a line
  says that a request was answered and not by whom -- which is the only
  thing worth knowing when two places disagree about who holds one.
  ```
  [next-middleware name]
  (http/journal
    next-middleware
    |(produce
       (logf "%s %s %s %s in %s, %s"
             name ($ :head) ($ :method) ($ :fulluri)
             ($ :elapsed) ($ :reqs)))))

(defn stacktrace
  "Create stacktrace event from the fiber `fib`."
  [fib]
  (make-effect
    (fn stacktrace [_ state _]
      (if (state :debug) (debug/stacktrace fib))) "stacktrace"))
