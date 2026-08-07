(use spork/test)
(import ../twm/app :prefix "")

# A transition is written into the image and read off the wire without ever
# being assembled again, so what it says has to be pinned exactly. These
# read the bytes, because the bytes are the whole contract with Datastar.

(defn- chunks
  ```
  The chunks of a document, each as `[declared-length body]`.

  Reading the declared length rather than trusting it is the point: a chunk
  whose header lies about its body is one malformed event to Datastar, and
  it patches nothing at all.
  ```
  [document]
  (def out @[])
  (var rest document)
  (while (def at (string/find "\r\n" rest))
    (def size (scan-number (string "0x" (string/slice rest 0 at))))
    (array/push out [size (string/slice rest (+ at 2) (+ at 2 size))])
    (set rest (string/slice rest (+ at 2 size 2))))
  out)

(defn- bodies [document] (map 1 (chunks document)))

(start-suite :one-message)
(let [[[size body]] (chunks (ds/msg/remove-elements "#totals"))]
  (assert (= size (length body)) "a removal declares its own length")
  (assert (= body "event: datastar-patch-elements\ndata: mode remove\ndata: selector #totals\n\n")
          "and says mode before selector, with nothing else in it"))

(let [[[size body]] (chunks (ds/msg/beat "#stage" "/content" "500ms"))]
  (assert (= size (length body)) "the beat declares its own length")
  (assert (string/find "data: mode append" body) "the beat is appended, not replacing")
  (assert (string/find "data: selector #stage" body) "and appended where it was told")
  (assert (string/find "data-init__delay.500ms" body) "it waits by attribute")
  (assert (string/find "@get('/content')" body) "and reopens the stream itself")
  (assert (not (string/find "<script" body)) "with no script anywhere in it"))
(end-suite)

(start-suite :multiline-elements)
# A field in an event stream ends at the newline. Markup that carries one
# has to be spread over a `data:` line each, or it ends the field early and
# Datastar empties the selector instead of replacing it.
(let [[[size body]] (chunks (ds/msg/patch-elements
                              "<style id=\"skin\">\na { color: red; }\n</style>"
                              "#skin" "outer"))]
  (assert (= size (length body)) "the chunk still declares its true length")
  (assert (= 3 (length (string/find-all "data: elements " body)))
          "one data line per line of markup")
  (assert (not (string/find "\n<style" body)) "no line begins with markup")
  (assert (not (string/find "\na { color" body)) "not the middle either")
  (assert (not (string/find "\n</style>" body)) "nor the end")
  (assert (string/has-suffix? "data: elements </style>\n\n" body)
          "and the event ends where it should"))

(let [[[_ body]] (chunks (ds/msg/patch-elements "<p>one line</p>" "#p" "inner"))]
  (assert (= 1 (length (string/find-all "data: elements " body)))
          "single-line markup is unchanged"))
(end-suite)

(start-suite :a-whole-transition)
(def document
  (ds/transition :gone ["#totals" "#track"] :into "#stage"
                 :path "/content" :beat "300ms"))

(let [bs (bodies document)]
  (assert (= 3 (length bs)) "two removals and a beat")
  (assert (string/find "#totals" (bs 0)) "the first listener goes first")
  (assert (string/find "#track" (bs 1)) "then the second")
  (assert (string/find "mode remove" (bs 0)) "removals really remove")
  (assert (string/find "mode remove" (bs 1)) "both of them")
  # The beat must come last. Appended before a removal that matched it, the
  # reopening would be taken straight back out.
  (assert (string/find "data-init__delay.300ms" (bs 2)) "and the beat comes last")
  (assert (not (string/find "beat" (bs 0))) "nothing is appended before the removals")
  (assert (not (string/find "beat" (bs 1))) "nothing is appended between them"))

(each [size body] (chunks document)
  (assert (= size (length body)) "every chunk declares its true length")
  (assert (string/has-suffix? "\n\n" body) "and every message ends its event"))
(end-suite)

(start-suite :a-transition-is-a-constant)
# The point of the whole shape: two calls, same bytes, and no request in
# sight. If this ever stops holding, something is being decided per visitor.
(assert (= (ds/transition :gone ["#a"] :into "#stage")
           (ds/transition :gone ["#a"] :into "#stage"))
        "the same transition is the same string")
(assert (= (ds/transition :gone [] :into "#stage")
           (ds/msg/beat "#stage" "/content" "500ms"))
        "a transition that removes nothing is just its beat")
(assert (not= (ds/transition :gone ["#a"] :into "#stage")
              (ds/transition :gone ["#b"] :into "#stage"))
        "and two different transitions are different strings")
(end-suite)
