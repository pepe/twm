(use spork/test)
(import jhydro)
(import ../twm/navigation :prefix "")
(import ../twm/sentry :as sentry)
(import ../twm/tree :as tree)
(import ../twm/app :prefix "")

(defn person [password]
  (def key (string (jhydro/pwhash/keygen)))
  {:key key :secret (string (jhydro/pwhash/create password key))})

(def dan (person "dan's secret"))
(def matej (person "matej's secret"))

(defn config [&opt identities]
  @{:name "locker"
    :runtime {:debug false :log false}
    :symbionts @{:sentry @{:entry "sentry.janet"
                           :identities (or identities {:dan dan :matej matej})}
                 :dan @{:entry "avatar.janet" :guarded-by :sentry}
                 :matej @{:entry "avatar.janet" :guarded-by :sentry}}
    :mycelium @{:psk "k"
                :nodes @{:sentry @{:rpc "localhost:1" :peers [:tree]}
                         :dan @{:rpc "localhost:2"}
                         :matej @{:rpc "localhost:3"}
                         :tree @{:rpc "localhost:4"}}}
    :membrane @{:nodes @{:dan @{:http "localhost:7790" :entrance true}
                         :matej @{:http "localhost:7791" :entrance true}}}})

(defn sentry-state [conf]
  ((=>symbiont/initial-state :sentry) conf))

(defn refusal [conf]
  (def [ok err] (protect (sentry-state conf)))
  (if ok :accepted err))

(start-suite :identities-places)
(def state (sentry-state (config)))
(def spaces (state :spaces))
(assert (= :dan (get-in spaces [:dan :owner])) "Dan's place is owned by Dan")
(assert (= :matej (get-in spaces [:matej :owner])))
(assert (= (dan :key) (get-in spaces [:dan :key])))
(assert (= (matej :secret) (get-in spaces [:matej :secret])))
(assert (= :dan (place/owner state (spaces :dan))))
(assert (= :sentry (place/owner state state)) "the guardian's own place is its own")
(assert (deep= @[:dan :matej :sentry] (session/owners state)))
(end-suite)

(start-suite :identities-refused)
(assert (string/find "matej has no identity" (refusal (config {:dan dan}))))
(assert (string/find "eve is not guarded by sentry"
                     (refusal (config {:dan dan :matej matej :eve (person "e")}))))
(assert (string/find "matej shares a key with dan"
                     (refusal (config {:dan dan :matej (merge matej {:key (dan :key)})}))))
(assert (string/find "matej needs :secret and :key"
                     (refusal (config {:dan dan :matej {:key "k2"}}))))
(def two-doors (config))
(put-in two-doors [:membrane :nodes :matej :entrance] false)
(assert (string/find "matej is not an entrance" (refusal two-doors)))
(def one-door (config))
(put-in one-door [:symbionts :sentry :identities] nil)
(put-in one-door [:symbionts :sentry :secret] (dan :secret))
(assert (string/find "exactly one entrance" (refusal one-door))
        "without identities the one-entrance rule holds as it always did")
(end-suite)

(start-suite :identities-views)
(def state (sentry-state (config)))
(def manager (make-manager state))
(:transact manager (sentry/^prepare-view {}))
(:await manager)
(def dan-view (get-in state [:spaces :dan :view]))
(def matej-view (get-in state [:spaces :matej :view]))
(assert (= :dan (dan-view :owner)))
(assert (jhydro/pwhash/verify (dan-view :secret) "dan's secret" (dan-view :key))
        "Dan's door asks Dan's secret")
(assert (not (jhydro/pwhash/verify (dan-view :secret) "matej's secret" (dan-view :key)))
        "Matej's secret does not open Dan's door")
(assert (jhydro/pwhash/verify (matej-view :secret) "matej's secret" (matej-view :key)))
(end-suite)

(start-suite :identities-caps)
(def state (sentry-state (config)))
(def sessions @{})
(tree/sessions/record sessions "dan-1" :dan {:holder "password"})
(tree/sessions/record sessions "dan-2" :dan {:holder "locker/dan"})
(tree/sessions/record sessions "matej-1" :matej {:holder "password"})
(def asked @[])
(put state :tree
     @{:stream true
       :snapshot (fn [_ colls owner]
                   (array/push asked owner)
                   {:values {:cap/session (tree/session/cap (get sessions owner {}))}})})
(def manager (make-manager state))
(:transact manager (sentry/^prepare-view {}) (projection/^refresh [:cap/session]))
(:await manager)
(assert (deep= @[:dan :matej :sentry] asked) "one snapshot per owner")
(defn admits? [place token]
  ((get-in state [:spaces place :view :cap/session])
    {:headers {"Cookie" {"session" token}}}))
(assert (admits? :dan "dan-1"))
(assert (admits? :dan "dan-2") "two sessions of one door are live together")
(assert (not (admits? :dan "matej-1")) "Matej's session does not open Dan's place")
(assert (admits? :matej "matej-1"))
(assert (not (admits? :matej "dan-1")))
(assert ((get-in state [:spaces :dan :view :cap/session])
          {:headers {"Authorization" (sentry/bearer "dan-2")}})
        "a session is admitted as a bearer too")
(:transact manager (^session/caps {:matej (tree/session/cap {})}))
(:await manager)
(assert (not (admits? :matej "matej-1")) "an owner's capability reaches its places")
(assert (admits? :dan "dan-1") "and no other owner's")
(end-suite)

(start-suite :sessions-record)
(def sessions @{})
(tree/sessions/record sessions "a" :dan {:holder "locker/dan"})
(tree/sessions/record sessions "b" :dan {:holder "password"})
(tree/sessions/record sessions "c" :dan {:holder "locker/dan"})
(assert (= 3 (length (sessions :dan))) "a sign-in adds, never replaces")
(tree/sessions/record sessions "" :dan {:token "b"})
(assert (deep= @{"a" "locker/dan" "c" "locker/dan"} (sessions :dan)) "one session ends")
(tree/sessions/record sessions "" :dan {:holder "locker/dan"})
(assert (empty? (sessions :dan)) "everything one holder holds ends")
(tree/sessions/record sessions "d" :dan)
(tree/sessions/record sessions "" :dan)
(assert (empty? (sessions :dan)) "the bare empty session still ends the door's every session")
(def cap (tree/session/cap @{"x" true "" true}))
(assert (not (cap {:headers {"Cookie" {"session" ""}}})) "the empty token is never live")
(assert (not (cap {:headers {"Authorization" "Bearer "}})))
(assert ((tree/session/cap "legacy") {:headers {"Cookie" {"session" "legacy"}}})
        "a tree keeping one session string still works")
(end-suite)

(start-suite :sessions-presented)
(assert (deep= @["t1" "t2" "b"]
               (sentry/session/presented
                 {:headers {"Cookie" "a=1; session=t1; session=t2"
                            "Authorization" "Bearer b"}})))
(assert (deep= @["t"] (sentry/session/presented {:headers {"Cookie" {"session" "t"}}})))
(assert (deep= @["t" "u"]
               (sentry/session/presented {:headers {"Cookie" {"session" @["t" "u"]}}})))
(assert (empty? (sentry/session/presented {:headers {"Authorization" "Basic x"}})))
(end-suite)
