(import ./thicket :prefix "")

(setdyn *handler-defines* [:view :conn])
(defdyn *view* "View for handlers")

(defn ^session/new
  "Saves new session on the tree"
  [session]
  (if session
    (make-effect
      (fn [_ {:tree tree :tenant tenant :name name} _]
        (default tenant name)
        (:session/new tree tenant session))
      "new session")
    Empty))

(defn- guarded/surface
  ```
  The surface `guarded` presents to the outside: the membrane node it
  declares, and beside it the address of every neighbour that node names.
  ```
  [config guarded]
  (def node (get-in config [:membrane :nodes guarded]))
  (def surface (if node (merge @{} node) @{}))
  (each neighbour (get surface :neighbors [])
    (put surface neighbour (get-in config [:membrane :nodes neighbour :address])))
  surface)

(defn =>sentry/initial-state
  ```
  Navigation to sentry initial state.

  Guarding is inhabiting a membrane. A sentry stands in the guarded
  symbiont's place on the outside, so it takes that symbiont's membrane
  and the rpc address it must answer on, and nothing else. Its peers are
  its own, declared on the sentry: whom a symbiont speaks to is not part
  of the surface it presents.

  Which symbionts those are comes from `=>guardian/spaces`, never from the
  guardian's own config. Each becomes a living space it holds and can give
  up again; its own address and its own peers stay its own, because a
  guardian that outlives a handover must be reachable as itself while it
  stands in another's place.
  ```
  [sentry]
  (let [t @{} spaces @{}]
    (=> (<:= t (=>mycelium/peers (=> :symbionts sentry)))
        (fn [config]
          (each guarded ((=>guardian/spaces sentry) config)
            (put spaces guarded
                 (merge (guarded/surface config guarded)
                        @{:name guarded
                          :guards guarded
                          :tenant (or (get-in config [:symbionts guarded :tenant])
                                      guarded)
                          :rpc (get-in config
                                       [:mycelium :nodes guarded :rpc])})))
          config)
        (<:- t :spaces (fn [&] spaces))
        (fn [config]
          # A guardian registers for one tenant, so the places it holds
          # must belong to one. Guarding across tenants is a shape nobody
          # has needed; it should be said out loud before it is allowed.
          (def tenants (distinct (map |($ :tenant) (values spaces))))
          (assert (>= 1 (length tenants))
                  (string "Guardian " sentry " would stand in places of "
                          (length tenants) " tenants, and registers for one."))
          (if-let [tenant (first tenants)] (put t :tenant tenant))
          config)
        (>base t))))

(defn ^place/leave
  ```
  Gives up the place this symbiont holds for `place`.

  A guardian holding it as a space lets go of its addresses and lives on,
  keeping its peers, its registration and its session for the next time
  the place falls empty. One whose whole membrane is that place has
  nothing to let go of short of itself, and exits as it always did.
  ```
  [place]
  (make-watch
    (fn [_ state _]
      (if-let [space (get-in state [:spaces place])]
        (^space/vacate space)
        Exit))
    (. "leave " place)))

(defn ^place/resume
  "Takes back the living space this symbiont holds for `place`."
  [place]
  (make-watch
    (fn [_ state _]
      (if-let [space (get-in state [:spaces place])]
        (^space/resume space)))
    (. "resume " place)))

(def- rpc/guardian
  ```
  What every guardian answers, beside whatever its project adds: the
  demiurge asks it to take a place back when the symbiont holding it goes.
  ```
  @{:space/resume
    (fnr :space/resume [produce-resp ok-resp]
         (def [place] args)
         [(^place/resume (keyword place))])})

(define-watch Spawn
  "Write spawn to aether"
  [_ {:guarded-by sentry} _]
  (^aether/spawn sentry ""))

(define-watch SpawnExit
  "Conditionaly spawn and exits the manager"
  [_ {:guarded-by sentry :name name} _]
  (producer
    (if sentry (produce Spawn))
    (produce Exit)))

(defh /logout
  "Clears the current session; guarded dashboards then hand control back to sentry."
  []
  (define :view)
  (produce (^session/new ""))
  (if (view :guarded-by)
    (produce SpawnExit))
  (http/see-other "/"))

(defn =>session/?eq
  "Creates session check function from `key`"
  [key]
  (if key
    (=<> :headers "Cookie" "session" (?eq key))
    (>base false)))

(defn check-session
  ```
  Checks if user cookie is in the session. If it is found  `next-middleware`
  is called. If the session is not found it exits.
  ```
  [next-middleware]
  (http/cookies
    (fn check-session [req]
      (define :view)
      (if-let [ck ((view :cap/session) req)]
        (next-middleware req)
        (http/not-authorized)))))

(defn session/check-with
  ```
  Checks if user cookie is in the session. If it is found  `next-middleware`
  is called. If the session is not found it exits.
  ```
  [not-auth]
  (fn [next-middleware]
    (http/cookies
      (fn check-session [req]
        (define :view)
        (if-let [ck ((view :cap/session) req)]
          (next-middleware req)
          (http/not-authorized not-auth
                               (http/content-type ".html")))))))

(def <form/>
  "Shared sentry login form."
  [:form {:method "POST" :class "f-col center"}
   [:input {:type "password" :name "secret"}]
   [:button [:strong "Use"]]])

(defn ^prepare-view
  "Initializes the shared sentry handler view with project templates."
  [templates]
  (make-event
    {:update
     (fn [_ state]
       # One capability, held by every view. It belongs to the tenant, not
       # to any one of its places, so a single push must reach them all.
       (def cap (>base false))
       # Where a session is granted for this tenant: the place the guardian
       # holds for the tenant's own symbiont. The other places send anyone
       # without a session there, and have no other way to know of it.
       (def home
         (some |(if (= ($ :guards) ($ :tenant)) ($ :address))
               (values (get state :spaces {}))))
       (defn view/of [place]
         (merge (select-keys state [:name :secret :key])
                (select-keys place [:guards :public :cookie-host :address :tenant])
                @{:cap/session cap :templates templates :tenant/address home}))
       (each space (values (get state :spaces {}))
         (merge-into space (select-keys state [:log :debug]))
         (put space :view (view/of space)))
       (put state :view (view/of state)))
     :effect
     (fn [_ state _]
       (setdyn :view (state :view)))}
    "prepare sentry view"))

(defh index
  "Renders the sentry form or an optional dormant-session resume page."
  [http/cookies]
  (define :view)
  (define :conn)
  (def {:page page :title title :success success :resume resume} (view :templates))
  (def {:guards guards :address address} view)
  (if-let [ck ((view :cap/session) req)]
    (if resume
      (http/html-success-resp (page (resume guards)))
      (do
        (protect
          (:write conn
                  (http/html-success-resp
                    (page @[(success guards) (<script/redirect/> address)])))
          (:flush conn))
        (ev/give-supervisor :close conn)
        (produce (^aether/spawn guards "") (^place/leave guards))
        {}))
    (http/html-success-resp
      (page @[(if (function? title) (title (human guards)) title)
              <form/>]))))

(defh /continue
  "Starts the guarded symbiont after a valid dormant sentry session."
  [http/cookies]
  (define :view)
  (define :conn)
  (def {:page page :success success} (view :templates))
  (def {:guards guards :address address} view)
  (if-let [ck ((view :cap/session) req)]
    (do
      (protect
        (:write conn
                (http/html-success-resp
                  (page @[(success guards) (<script/redirect/> address)])))
        (:flush conn))
      (ev/give-supervisor :close conn)
      (produce (^aether/spawn guards "") (^place/leave guards))
      {})
    (http/see-other "/")))

(defh auth
  "Authenticates a sentry secret and publishes its session."
  [http/urlenc-post]
  (define :view)
  (define :conn)
  (def {:page page :success success :failure failure} (view :templates))
  (if-let [sec (view :secret)
           bsec (get body :secret "")
           {:cookie-host cookie-host :key key
            :guards guards :address address} view
           _ (pwhash/verify sec bsec key)]
    (let [sk (derive-from key)]
      (fn [conn]
        (def resp
          (page @[(success guards) (<script/redirect/> address)]))
        (protect
          (:write conn
                  (http/html-success-resp
                    resp
                    (http/cookie
                      "session"
                      (string sk "; Secure; HttpOnly; Domain="
                              cookie-host ";"))))
          (:flush conn))
        (ev/give-supervisor :close conn)
        (produce (^session/new sk))
        (produce (^aether/spawn guards "") (^place/leave guards))))
    (http/html-success-resp (page @[failure <form/>]))))

(defh inhabited
  ```
  Serves a place the guardian holds for a symbiont other than the tenant's
  own. There is no secret to offer here: the session is granted at the
  tenant's door, and this door only asks whether it was.
  ```
  [http/cookies]
  (define :view)
  (define :conn)
  (def {:page page :success success :unauthorized unauthorized} (view :templates))
  (def {:guards guards :address address :tenant/address home} view)
  (if-let [ck ((view :cap/session) req)]
    (do
      (protect
        (:write conn
                (http/html-success-resp
                  (page @[(success guards) (<script/redirect/> address)])))
        (:flush conn))
      (ev/give-supervisor :close conn)
      (produce (^aether/spawn guards "") (^place/leave guards))
      {})
    (http/not-authorized (unauthorized guards home)
                         (http/content-type ".html"))))

(defn routes
  ```
  Builds the routes of one living space.

  The tenant's own place is where a session is granted, and it alone
  carries the form, the resume and the logout. Every other place the
  guardian holds asks only whether that grant happened.
  ```
  [templates place]
  (if (not= (place :guards) (place :tenant))
    @{"/" (http/dispatch {"GET" inhabited})}
    (merge
      (if (get templates :fallback false)
        @{:not-found (http/dispatch {"GET" index "POST" auth})}
        @{"/" (http/dispatch {"GET" index "POST" auth})})
      @{"/continue" (http/dispatch {"GET" /continue})
        "/logout" (http/dispatch {"GET" /logout})})))

(defn ^assemble
  ```
  Assembles shared sentry HTTP routes and RPC functions.

  Every address the sentry answers on gets the same functions, its own and
  each one it stands in for: the tree pushes a tenant's capability to
  whoever inhabits that tenant's address, and it must find a `:refresh`
  there whether the symbiont or its guardian is holding it.
  ```
  [templates rpc-funcs]
  (make-update
    (fn [_ state]
      (each place [state ;(values (get state :spaces {}))]
        (update place :rpc (update-rpc (merge rpc/guardian rpc-funcs))))
      (each space (values (get state :spaces {}))
        (put space :routes (routes templates space))
        (put space :static false))
      state)
    "assemble sentry"))

(defn run
  ```
  Runs the shared sentry lifecycle around project templates and start events.

  It announces itself on the Aether as every other symbiont does. A sentry
  that hands its place over by dying had nothing to announce and no one to
  hear it; one that outlives the handover is a peer the demiurge has to be
  able to reach, and the demiurge learns an address is answering only from
  the readiness that crosses the Aether.
  ```
  [config templates rpc-funcs start & before]
  (-> config
      (make-manager on-error)
      (:transact ;before
                 (^prepare-view templates)
                 (^assemble templates rpc-funcs)
                 HTTP
                 (^connect-peers start Exit)
                 AetherReady)
      :await))

(defmacro main
  "Defines a sentry executable entry point around `run`."
  [config templates rpc-funcs start & before]
  ~(defn main
     "Main entry into a sentry executable."
     [_ & _args]
     (,run ,config ,templates ,rpc-funcs ,start ,;before)
     (,os/exit 0)))
