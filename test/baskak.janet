(use spork/test)
(import ../twm/yarlyk :prefix "")
(import ../twm/baskak :prefix "")

(def pair (yarlyk/keygen))
(def now 1761990000)
(def live @{:dan "dan-session" :matej "matej-session"})
(defn grounds? [avatar session] (= session (get live avatar)))

(def baskak
  @{:thicket "locker" :name "baskak" :sign-key (pair :secret-key) :yarlyk/ttl 60
    :grants [{:avatar :dan :door "interstudy/dan-sentry" :admin true}
             {:avatar :matej :door "interstudy/matej-sentry" :admin true}
             {:avatar :dan :door "archive/viewer-sentry" :viewer true}]})

(defn ask [request] (baskak/warrant baskak request grounds? now))

(def door
  @{:issuers [(pair :public-key)] :door "interstudy/dan-sentry"
    :consequence :session/open :max-ttl 120 :started 0 :seen @{}})

(start-suite :baskak-warrant)
(def wire (ask {:avatar :dan :session "dan-session"
                :door "interstudy/dan-sentry" :capability :admin}))
(def [status claims] (yarlyk/verify wire door now))
(assert (= :ok status) "a granted avatar with a live session gets a warrant")
(assert (= "locker/dan" (claims :avatar)))
(assert (= "locker/baskak" (claims :issuer)))
(assert (= :admin (claims :capability)))
(assert (= (+ now 60) (claims :expires)) "validity is the Baskak's ttl")
(end-suite)

(start-suite :baskak-refusals)
(assert (= [:refused :grounds]
           (ask {:avatar :dan :session "stale"
                 :door "interstudy/dan-sentry" :capability :admin}))
        "no live session, no warrant")
(assert (= [:refused :grounds]
           (ask {:avatar :dan :session "matej-session"
                 :door "interstudy/dan-sentry" :capability :admin}))
        "another avatar's session is no ground")
(assert (= [:refused :grounds]
           (ask {:avatar :dan :session ""
                 :door "interstudy/dan-sentry" :capability :admin}))
        "the ended session is no ground")
(assert (= [:refused :grant]
           (ask {:avatar :dan :session "dan-session"
                 :door "interstudy/matej-sentry" :capability :admin}))
        "Dan is not granted Matej's door")
(assert (= [:refused :grant]
           (ask {:avatar :dan :session "dan-session"
                 :door "archive/viewer-sentry" :capability :admin}))
        "a viewer grant never warrants admin")
(assert (= [:refused :malformed] (ask "dan")))
(assert (= [:refused :malformed] (ask {:avatar "dan" :door "x" :capability :admin})))
(assert (dictionary? (ask {:avatar :dan :session "dan-session"
                           :door "archive/viewer-sentry" :capability :viewer}))
        "the same avatar holds a different capability elsewhere")
(end-suite)

(start-suite :baskak-grants-change)
(def request {:avatar :matej :session "matej-session"
              :door "interstudy/dan-sentry" :capability :admin})
(assert (= [:refused :grant] (ask request)))
(def before (baskak :grants))
(put baskak :grants [;before {:avatar :matej :door "interstudy/dan-sentry" :admin true}])
(assert (dictionary? (ask request)) "a grant added: same avatar, same session, a warrant")
(put baskak :grants before)
(assert (= [:refused :grant] (ask request)) "the grant removed: refused again")
(end-suite)

(start-suite :baskak-grants)
(assert (deep= @[{:door "interstudy/dan-sentry" :capability :admin}
                 {:door "archive/viewer-sentry" :capability :viewer}]
               (baskak/grants (baskak :grants) :dan)))
(assert (empty? (baskak/grants (baskak :grants) :eve)))
(end-suite)
