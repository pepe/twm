(use spork/test)
(import ../twm/thicket :prefix "")
(import ../twm/tree)
(import ../twm/schema)

(start-suite :socket-config-and-renewal)
(assert (schema/url? "unix:/tmp/tree.sock"))
(assert-not (schema/url? "unix:tree.sock") "A relative socket path is refused")
(assert (schema/config/mycelium/node? {:rpc "unix:/tmp/tree.sock" :peers [:bill]}))
(assert (schema/config/membrane/http-node?
          {:http "unix:/tmp/http.sock" :socket-mode 8r660 :address "https://bill.pan.earth"}))
(assert-not (schema/config/membrane/http-node?
              {:http "unix:/tmp/http.sock" :socket-mode 8r666}) "World-writable sockets are refused")
(let [closed @[]
      client @{:host :unix :port "/tmp/tree.sock" :close (fn [_] (array/push closed true))}
      state @{:tree client}
      manager (make-manager state)]
  (:transact manager (^peer/renew :tree "unix:/tmp/tree.sock"))
  (assert (= client (state :tree)) "Renewing a Unix endpoint keeps its connection")
  (assert (empty? closed))
  (:transact manager (tree/^peer/restore :tree))
  (assert (= "unix:/tmp/tree.sock" (state :tree)) "Disconnect restores the Unix transport"))
(end-suite)

(unless (= :windows (os/which))
  (def dir (string "/tmp/twm-socket-test-" (os/getpid)))
  (os/mkdir dir)
  (os/chmod dir 8r700)
  (start-suite :socket-place-handover)
  (def url (string "unix:" dir "/http.sock"))
  (def first @{:name :guardian :view @{} :socket-mode 8r660})
  (def second @{:name :bill :view @{}})
  (def channel (ev/chan 8))
  (space/listen first :http channel url)
  (assert (= 8r660 (os/stat (string dir "/http.sock") :int-permissions)))
  (assert-error "A bill cannot bind until its guardian releases" (space/listen second :http channel url))
  (space/let-go first)
  (space/listen second :http channel url)
  (space/let-go first)
  (assert (os/lstat (string dir "/http.sock")) "An old space cannot unlink the current holder")
  (space/let-go second)
  (:transact (make-manager) (^space/resume first))
  (assert (get (readiness/status (first :view)) :ready) "Resuming the guardian opens its gate")
  (let [connection (net/connect :unix (string dir "/http.sock"))]
    (assert connection "The guardian owns the same door again")
    (ev/with-deadline 1
      (forever
        (def [tag accepted] (ev/take channel))
        (when (= tag :conn) (:close accepted) (break))))
    (:close connection))
  (space/let-go first)
  (ev/sleep 0.01)
  (ev/chan-close channel)
  (end-suite)
  (each file (os/dir dir) (os/rm (string dir "/" file)))
  (os/rmdir dir))
