(use spork/test)
(import ../twm/thicket :prefix "")
(import ../twm/demiurge :prefix "")

# The heartbeat decides which peers get killed and raised, and it decides it
# from three tables that other events keep writing to. What has repeatedly
# been got wrong here is not what a decision does but which one gets made,
# so these read the events `CheckPeers` and `PingPeers` return instead of
# transacting them -- transacting reaches for real processes.
(defn decisions
  "Names of the events a watch chooses for `state`."
  [event state]
  (map |(if (table? $) ($ :name) $) ((event :watch) nil state nil)))

(defn thicket
  "A demiurge state holding only what the heartbeat looks at."
  [&named spawned misses activity autostart timeout]
  @{:timeout (or timeout 60)
    :autostart (or autostart [])
    :view @{:ran true :spawned (or spawned @{})
            :misses (or misses @{})
            :activity (or activity @{})}})

(defn long-ago [] (- (os/time) 600))

(start-suite :fleet-excludes-handles)
# :entries also contains dmc/cmc for explicit handle builds. They are not
# symbionts and cannot use peer configuration or peer deployment.
(let [state @{:builds [:tree :pepe]
              :entries {:tree "tree.janet" :pepe "dashboard.janet"
                        :dmc "dmc.janet" :cmc "cmc.janet"}}]
  (assert (deep= @["build peer tree" "build peer pepe"] (decisions Build state)))
  (assert (deep= @["deploy peer tree" "deploy peer pepe"] (decisions Deploy state)))
  (assert (not (peer/buildable? state :dmc)))
  (assert (not (peer/buildable? state :cmc))))
(end-suite)

(start-suite :test-subprocess-results)
(let [file (path/join (or (os/getenv "TEMP") "/tmp")
                      (string "twm-test-child-" (os/getpid) ".janet"))
      state @{:test @{:total 0 :passed 0 :failing @[]}}
      manager (make-manager state)]
  (defer (os/rm file)
    (spit file "(print \"child stdout\") (eprint \"child stderr\") (os/exit 0)")
    (:transact manager (^test/file file))
    (:await manager)
    (assert (= 1 (get-in state [:test :total])))
    (assert (= 1 (get-in state [:test :passed]))
            "redirected test subprocess can write to stdout and stderr")
    (spit file "(os/exit 7)")
    (:transact manager (^test/file file))
    (:await manager)
    (assert (= 2 (get-in state [:test :total])))
    (assert (deep= @[file] (get-in state [:test :failing]))
            "nonzero subprocess exit remains a test failure")))
(end-suite)

(start-suite :peer-removal)
# A peer is removed when its process exits. Heartbeat state names a peer,
# not a process, so anything left behind is inherited by its replacement.
(let [state @{:view @{:spawned @{:pepe :mycelium}
                      :misses @{:pepe 3}
                      :activity @{:pepe (long-ago)}}}]
  (:transact (make-manager state) (^peer/remove :pepe))
  (assert (nil? (get-in state [:view :spawned :pepe])) "removed peer is not spawned")
  (assert (nil? (get-in state [:view :misses :pepe])) "removed peer keeps no misses")
  (assert (nil? (get-in state [:view :activity :pepe])) "removed peer keeps no activity"))

# Removal must not disturb the peers standing beside it.
(let [state @{:view @{:spawned @{:pepe :mycelium :tree :mycelium}
                      :misses @{:pepe 3 :tree 1}
                      :activity @{:pepe (long-ago) :tree 42}}}]
  (:transact (make-manager state) (^peer/remove :pepe))
  (assert (= :mycelium (get-in state [:view :spawned :tree])) "neighbour still spawned")
  (assert (= 1 (get-in state [:view :misses :tree])) "neighbour keeps its misses")
  (assert (= 42 (get-in state [:view :activity :tree])) "neighbour keeps its activity"))
(end-suite)

(start-suite :checking-reached-peers)
# Three missed pings is a peer that is there and not answering: end it and
# raise it again.
(let [d (decisions CheckPeers
                   (thicket :spawned @{:pepe :mycelium} :misses @{:pepe 3}))]
  (assert (index-of "restart peer pepe" d) "a peer that missed three pings is stopped")
  (assert (index-of "restart peer pepe" d) "a peer that missed three pings is replaced"))

# Two is not yet three.
(let [d (decisions CheckPeers
                   (thicket :spawned @{:pepe :mycelium} :misses @{:pepe 2}))]
  (assert (not (index-of "restart peer pepe" d)) "two missed pings is not enough to stop")
  (assert (not (index-of "run peer pepe" d)) "two missed pings is not enough to raise"))

# Going quiet past the thicket's patience is a peer with nothing to do. It
# is stopped and left down; only a peer the thicket wants standing comes
# back, and that is the autostart branch's business, not this one's.
(let [d (decisions CheckPeers
                   (thicket :spawned @{:pepe :mycelium}
                            :activity @{:pepe (long-ago)}))]
  (assert (index-of "stop peer pepe" d) "a peer quieter than the timeout is stopped")
  (assert (not (index-of "run peer pepe" d)) "a peer stopped for quiet is not raised"))

(let [d (decisions CheckPeers
                   (thicket :spawned @{:pepe :mycelium}
                            :activity @{:pepe (os/time)}))]
  (assert (not (index-of "restart peer pepe" d)) "a peer active just now is left alone"))
(end-suite)

(start-suite :checking-booting-peers)
# A peer is :boot from the moment it is spawned until its Aether says it is
# ready. Its predecessor's heartbeat must not reach it: killing a peer for
# the silence of the one it replaced is how a thicket fails to come up.
(let [d (decisions CheckPeers
                   (thicket :spawned @{:pepe :boot}
                            :misses @{:pepe 3}
                            :activity @{:pepe (long-ago)}))]
  (assert (not (index-of "restart peer pepe" d)) "a booting peer is not stopped")
  (assert (not (index-of "run peer pepe" d)) "a booting peer is not raised again"))

# Nor is a booting peer wanted standing raised a second time: it is already
# there, just not yet reachable.
(let [d (decisions CheckPeers
                   (thicket :spawned @{:pepe :boot} :autostart [:pepe]))]
  (assert (not (index-of "run peer pepe" d)) "a booting autostart peer is not raised twice"))

# PingPeers must agree with CheckPeers about who is reachable, or a booting
# peer accrues misses it will be judged on the moment it is reached.
(let [d (decisions PingPeers
                   (thicket :spawned @{:pepe :boot :tree :mycelium}))]
  (assert (not (index-of "ping peer pepe" d)) "a booting peer is not pinged")
  (assert (index-of "ping peer tree" d) "a reached peer is pinged"))
(end-suite)

(start-suite :raising-the-wanted)
# A peer that dies leaves :spawned entirely, and nothing else here would
# look for it again.
(let [d (decisions CheckPeers (thicket :autostart [:tree]))]
  (assert (index-of "run peer tree" d) "an absent autostart peer is raised"))

(let [d (decisions CheckPeers
                   (thicket :spawned @{:tree :mycelium} :autostart [:tree]))]
  (assert (not (index-of "run peer tree" d)) "a standing autostart peer is left standing"))

# Peers raised on demand are not autostarted, and being absent is their
# ordinary condition.
(let [d (decisions CheckPeers (thicket :autostart [:tree]))]
  (assert (not (index-of "run peer pepe" d)) "an on-demand peer is not missed"))
(end-suite)

(start-suite :the-replacement-cycle)
# The whole of it: a reached peer stops answering, is stopped and raised,
# and the peer that comes up in its place is judged on its own silence
# rather than on its predecessor's.
(let [state (thicket :spawned @{:pepe :mycelium}
                     :misses @{:pepe 3}
                     :activity @{:pepe (long-ago)})
      manager (make-manager state)]
  (assert (index-of "restart peer pepe" (decisions CheckPeers state))
          "the unreachable peer is stopped")
  # ^peer/stop's own watch removes it; ^peer/run saves the replacement as
  # :boot. Both are done here directly, because transacting them would
  # reach for the process itself.
  (:transact manager (^peer/remove :pepe))
  (:transact manager (^peer/save-spawned :pepe :boot))
  (assert (= :boot (get-in state [:view :spawned :pepe])) "the replacement is booting")
  (assert (empty? (decisions CheckPeers state))
          "the replacement inherits no judgement from the peer it replaced")
  (:transact manager (^peer/save-spawned :pepe :mycelium))
  (assert (empty? (decisions CheckPeers state))
          "and none once it is reached, having missed nothing itself"))
(end-suite)
