(use spork/test)
(import ../twm/thicket :prefix "")

# A client redials by itself -- `:open` drops the line it holds and
# connects again -- so a peer that merely restarted needs nothing done to
# it. What `:open` cannot do is connect somewhere else: it reaches for the
# `:host` and `:port` the client was built with. A registration is the
# only moment a peer says where it now listens, and that is the one thing
# worth acting on.
#
# The other half of the contract matters as much: registering is routine,
# a listener renews its own every minute, so an address that has not
# changed must cost nothing at all.

(defn stub/client
  "A client that records its closing, and can be made to fail at it."
  [record &named host port fail-close]
  (default host "localhost")
  (default port "4645")
  @{:host host :port port
    :close (fn [self]
             (array/push record :close)
             (if fail-close (error "the far end is already gone") self))})

(start-suite :renewing-peers)

# The whole point: a peer that moved is followed.
(let [record @[]
      state @{:name :augur :psk "psk" :pepe (stub/client record)}]
  (:transact (make-manager state) (^peer/renew :pepe "localhost:4999"))
  (assert (= "localhost:4999" (state :pepe))
          "a peer that names a new address is followed there")
  (assert (deep= record @[:close])
          "the line to where it used to be is let go of"))

# The other half: the address is almost always the same one, and a line
# that already points at it must not be touched.
(let [record @[]
      client (stub/client record)
      state @{:name :augur :psk "psk" :pepe client}]
  (:transact (make-manager state) (^peer/renew :pepe "localhost:4645"))
  (assert (= client (state :pepe))
          "a peer that has not moved keeps the very line it had")
  (assert (empty? record)
          "and nothing is closed on a registration that is only routine"))

# What is left behind is a string, because that is what `^peer/connect`
# builds from -- the same shape `^peer/restore` leaves on the way out.
(let [state @{:name :augur :psk "psk" :pepe (stub/client @[])}]
  (:transact (make-manager state) (^peer/renew :pepe "localhost:4999"))
  (assert (string? (state :pepe))
          "a renewed peer is left in the state a connect rebuilds from"))

# A listener the augur has never dialled has no slot at all yet.
(let [state @{:name :augur :psk "psk"}]
  (:transact (make-manager state) (^peer/renew :pepe "localhost:4645"))
  (assert (= "localhost:4645" (state :pepe))
          "a peer heard from for the first time is simply recorded"))

# Nor has one that was configured but never connected.
(let [state @{:name :augur :psk "psk" :pepe "localhost:4645"}]
  (:transact (make-manager state) (^peer/renew :pepe "localhost:4999"))
  (assert (= "localhost:4999" (state :pepe))
          "an unconnected peer takes the address it now names"))

# A peer that moved is a peer whose old line is likely already gone, so
# the close is the likeliest thing here to raise -- and the least
# important. The new address must land regardless.
(let [record @[]
      state @{:name :augur :psk "psk"
              :pepe (stub/client record :fail-close true)}]
  (:transact (make-manager state) (^peer/renew :pepe "localhost:4999"))
  (assert (deep= record @[:close])
          "the close is attempted even though it raises")
  (assert (= "localhost:4999" (state :pepe))
          "a close that fails does not keep the new address out"))

# Renewing one peer says nothing about any other, and a thicket is mostly
# other peers.
(let [state @{:name :augur :psk "psk"
              :pepe (stub/client @[])
              :todo (stub/client @[] :port "4647")}]
  (:transact (make-manager state) (^peer/renew :pepe "localhost:4999"))
  (assert (table? (state :todo))
          "renewing one peer leaves every other line standing"))

# Arriving twice with the same news is harmless: the second finds the
# address already recorded.
(let [record @[]
      state @{:name :augur :psk "psk" :pepe (stub/client record)}
      manager (make-manager state)]
  (:transact manager (^peer/renew :pepe "localhost:4999"))
  (:transact manager (^peer/renew :pepe "localhost:4999"))
  (assert (deep= record @[:close])
          "a peer already renewed is not closed a second time")
  (assert (= "localhost:4999" (state :pepe))
          "and the address it moved to is still what stands"))

(end-suite)
