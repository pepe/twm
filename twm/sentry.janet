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

(defn =>sentry/initial-state
  ```
  Navigation to sentry initial state.

  Guarding is inhabiting a membrane. A sentry stands in the guarded
  symbiont's place on the outside, so it takes that symbiont's membrane
  and the rpc address it must answer on, and nothing else. Its peers are
  its own, declared on the sentry: whom a symbiont speaks to is not part
  of the surface it presents.

  Which symbiont that is comes from `=>guardian/space`, never from the
  sentry's own config, and is collected here as `:guards` so the state
  still names the place this sentry stands in.
  ```
  [sentry]
  (let [c @[] t @{}
        =>guards (=>guardian/space sentry)]
    (=> (<:= t (=>mycelium/peers (=> :symbionts sentry)))
        (>if =>guards
             (=> (<- c =>guards)
                 (<:- t :guards (fn [&] (array/peek c)))
                 (<:- t :tenant (>or (=> :symbionts |(get $ (array/peek c)) :tenant)
                                     (fn [&] (array/peek c))))
                 (<:- t :rpc (=> :mycelium :nodes |(get $ (array/peek c)) :rpc))
                 (<:= t (=> :membrane :nodes |(get $ (array/peek c))))
                 (>if (=> :membrane :nodes |(get $ (array/peek c)))
                      (>if (=> :membrane :nodes |(get $ (array/peek c)) :neighbors)
                           (=> (<- c (=> :membrane :nodes |(get $ (array/peek c)) :neighbors))
                               (<:= t (=> :membrane :nodes
                                          |(tabseq [i :in (array/pop c)] i
                                             ((=> i :address) $)))))))))
        (>base t))))

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
       (put state :view
            (merge
              (select-keys state [:name :guards :secret :key
                                  :public :cookie-host :address])
              @{:cap/session (>base false)
                :templates templates})))
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
        (produce (^aether/spawn guards ""))
        (produce Exit)
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
      (produce (^aether/spawn guards ""))
      (produce Exit)
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
        (produce (^aether/spawn guards ""))
        (produce Exit)))
    (http/html-success-resp (page @[failure <form/>]))))

(defn routes
  "Builds shared sentry routes; templates may request a fallback route."
  [templates]
  (merge
    (if (get templates :fallback false)
      @{:not-found (http/dispatch {"GET" index "POST" auth})}
      @{"/" (http/dispatch {"GET" index "POST" auth})})
    @{"/continue" (http/dispatch {"GET" /continue})
      "/logout" (http/dispatch {"GET" /logout})}))

(defn ^assemble
  "Assembles shared sentry HTTP routes and RPC functions."
  [templates rpc-funcs]
  (make-update
    (fn [_ state]
      ((=> (>put :routes (routes templates))
           (>put :static false)
           (>update :rpc (update-rpc rpc-funcs)))
        state))
    "assemble sentry"))

(defn run
  "Runs the shared sentry lifecycle around project templates and start events."
  [config templates rpc-funcs start & before]
  (-> config
      (make-manager on-error)
      (:transact ;before
                 (^prepare-view templates)
                 (^assemble templates rpc-funcs)
                 HTTP
                 (^connect-peers start Exit))
      :await))

(defmacro main
  "Defines a sentry executable entry point around `run`."
  [config templates rpc-funcs start & before]
  ~(defn main
     "Main entry into a sentry executable."
     [_ & _args]
     (,run ,config ,templates ,rpc-funcs ,start ,;before)
     (,os/exit 0)))
