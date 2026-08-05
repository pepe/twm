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
        (produce (diag "session-new name=" name " tenant=" tenant
                       " present=" (present-string? session)
                       " length=" (length session)))
        (:session/new tree tenant session))
      "new session")
    Empty))

(defn session/settled?
  ```
  Whether the tree agrees `tenant`'s session is now `session`.

  Asked by offering the tree's own capability the very session in
  question: a capability only admits the session it was made from, so one
  that admits this session was made after the change landed.
  ```
  [tree tenant session]
  (match (protect ((:cap/session tree tenant)
                    {:headers {"Cookie" {"session" session}}}))
    [true admitted] (truthy? admitted)
    # A tree that will not answer has not agreed to anything.
    false))

(defn ^session/end
  ```
  Ends `tenant`'s session, waits until the tree agrees it has ended, and
  only then produces `after`.

  The waiting is the whole of it. `:session/new` is answered before it is
  applied -- the tree's handler produces its events and the reply goes
  back while they are still to be transacted -- so anything that acted on
  the ending in that gap read the session that was. A symbiont that
  reported its place free straight afterwards had its guardian take the
  door back and read the old capability as it went, and the door opened
  again to the cookie just logged out.

  It is asked before any waiting, so an ending that has already landed
  costs nothing, and it gives up after a second rather than hold a door
  open on a tree that has stopped answering.
  ```
  [& after]
  (make-watch
    (fn [_ state _]
      (producer
        (def {:tree tree :name name} state)
        (def tenant (or (state :tenant) name))
        (produce (diag "session-end-begin name=" name " tenant=" tenant))
        (protect (:session/new tree tenant ""))
        (var settled (session/settled? tree tenant ""))
        (var tries 0)
        (while (and (not settled) (< tries 50))
          (ev/sleep 0.02)
          (++ tries)
          (set settled (session/settled? tree tenant "")))
        (produce (diag "session-end-settled name=" name " tenant=" tenant
                       " settled=" settled " tries=" tries))
        (if (present? after) (produce ;after))))
    "end session"))

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

(defn place/of
  ```
  The living space this symbiont holds for `place`, or nil.

  A symbiont raises its own place as well as every place it stands in for
  another, and `spaces` has always described the state itself as the
  first of them. Only the operations over places did not know it, so a
  symbiont could stand in a door and have no way to speak of it.
  ```
  [state place]
  (or (get-in state [:spaces place])
      (if (= place (state :name)) state)))

(defn ^place/leave
  ```
  Gives up the place this symbiont holds for `place`.

  Whoever holds it lets go of its addresses and lives on, keeping its
  peers, its registration and its session. Letting go is not dying: what
  the holder does afterwards -- stand in another door, or exit -- is its
  own affair, and is said by whoever asked it to leave.

  A `place` this symbiont does not hold is the old, blunt case: there is
  nothing to let go of short of itself, and it exits as it always did.
  ```
  [place]
  (make-watch
    (fn [_ state _]
      (if-let [space (place/of state place)]
        (^space/vacate space)
        Exit))
    (. "leave " place)))

(defn ^place/resume
  ```
  Takes back the living space this symbiont holds for `place`, and asks
  the tree what the tenant's session is before answering on it again.

  A guardian used to be born into a place it took back, and a newborn
  reads the session as it registers. One that outlives the handover has
  been standing elsewhere while the world changed, and the push telling
  it so is racing the first request through the door it just reopened --
  a logout loses that race, and the door opens to a session that ended.
  Reading on the way in does not race anything.
  ```
  [place]
  (make-watch
    (fn [_ state _]
      (if-let [space (place/of state place)]
        [(^tenant/refresh-view :cap/session)
         (^space/resume space)]))
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

(define-watch StandDown
  ```
  Gives up this symbiont's own place and exits.

  The order is the whole of it: the addresses close here and now, the
  place is reported free only once they have, and the exit comes last.
  Announcing first would send whoever acts on the report to a door still
  held, which is the mistake this replaces.

  The closing is done here rather than produced as an event for the same
  reason `space/let-go` exists at all -- a watch runs before any effect of
  the same transaction, so a released-place event would be announced
  before it had released anything.
  ```
  [_ state _]
  (def name (state :name))
  (if-let [space (place/of state name)] (space/let-go space))
  [(^aether/left name) Exit])

(defn- logout/settled
  "Returns an event that wakes a waiting logout response."
  [done]
  (make-effect
    (fn [_ _ _]
      (:give done true))
    "logout settled"))

(defn- handover/space
  "Releases only a guarded membrane space, never the sentry itself."
  [view]
  (when (view :guards)
    (space/let-go (view :space))))

(defn- logout/response
  "Returns a readiness page only after logout has settled on Tree."
  [done sent]
  (fn [conn]
    (ev/take done)
    (protect
      (:write conn
              (http/html-success-resp
                (hg/html
                  @[hg/doctype-html
                    [:html
                     [:body
                      [:p "Logged out." (<script/redirect/> "/")]]]]))))
    (protect (:flush conn))
    (:give sent true)
    (ev/give-supervisor :close conn)))

(defn- logout/standdown-after
  "Waits for the logout response before exiting the symbiont."
  [sent]
  (make-watch
    (producer
      (ev/take sent)
      (produce StandDown))
    "stand down after logout"))

(defh /logout
  ```
  Clears the current session.

  A symbiont serving this from its own membrane stands down afterwards, so
  its guardian takes the door back and asks for the secret again. A
  guardian serving it is already the one who would take the door back, and
  simply keeps standing.
  ```
  []
  (define :view)
  (def done (ev/chan 1))
  (def sent (ev/chan 1))
  (def settled (logout/settled done))
  (produce (diag "logout-request name=" (view :name)
                 " guarded=" (boolean (view :guards))
                 " own-space=" (boolean (view :space))
                 " session-cap=" (boolean (view :cap/session))))
  (produce
    # Close the local capability first, so in-flight requests cannot render
    # the old dashboard while Tree is applying the logout.
    (^session/cap false)
    (if (view :space)
      # A guardian keeps standing, so nobody takes the door back and reads
      # the capability on the way in. It has to read it itself, and by
      # asking rather than by being told: the tree's push reaches whoever
      # it can dial, and a guardian it cannot dial would go on admitting
      # the session it was holding.
      (^session/end (^tenant/refresh-view :cap/session) settled)
      # Signal the response before standing down: StandDown exits this
      # manager after closing the dashboard's address.
      (^session/end (^tenant/refresh-view :cap/session)
                    settled
                    (logout/standdown-after sent))))
  (logout/response done sent))

(defn =>session/?eq
  "Creates a session check function from a non-empty session `key`."
  [key]
  # The empty string is the logout sentinel. Janet considers it truthy,
  # so checking only `key` would let an empty Cookie match an ended session.
  (if (present-string? key)
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
      (produce (diag "session-check name=" (view :name)
                     " cookie-present=" (boolean (get-in req [:headers "Cookie" "session"]))
                     " cap-present=" (boolean (view :cap/session))))
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

(def <handover/>
  ```
  Header ending the connection that asked to be let through.

  A handover answers over a connection the asker will keep and reuse,
  and the next thing it sends down it is the redirect -- to a door the
  guardian has just closed. A closed door turns nobody away who never
  knocks. The connection has to end with the answer.
  ```
  {"Connection" "close"})

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
                @{:cap/session cap :templates templates :tenant/address home
                  :space place}))
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
        (handover/space view)
        (protect
          (:write conn
                  (http/html-success-resp
                    (page @[(success guards) (<script/redirect/> address)])
                    <handover/>))
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
      (handover/space view)
      (protect
        (:write conn
                (http/html-success-resp
                  (page @[(success guards) (<script/redirect/> address)])
                    <handover/>))
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
  (produce (diag "auth-request name=" (view :name)
                 " secret-present=" (boolean (view :secret))
                 " body-secret-present=" (present-string? (get body :secret ""))))
  (if-let [sec (view :secret)
           bsec (get body :secret "")
           {:cookie-host cookie-host :key key
            :guards guards :address address} view
           _ (pwhash/verify sec bsec key)]
    (let [sk (derive-from key)]
      (fn [conn]
        (produce (diag "auth-success name=" (view :name)
                       " guards=" guards " cookie-host=" cookie-host
                       " session-length=" (length sk)))
        (handover/space view)
        (def resp
          (page @[(success guards) (<script/redirect/> address)]))
        (protect
          (:write conn
                  (http/html-success-resp
                    resp
                    (merge <handover/>
                           (http/cookie
                             "session"
                             (string sk "; Secure; HttpOnly; Domain="
                                     cookie-host ";")))))
          (:flush conn))
        (ev/give-supervisor :close conn)
        (produce (^session/new sk))
        (produce (^aether/spawn guards "") (^place/leave guards))))
    (do
      (produce (diag "auth-failure name=" (view :name)))
      (http/html-success-resp (page @[failure <form/>])))))

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
      (handover/space view)
      (protect
        (:write conn
                (http/html-success-resp
                  (page @[(success guards) (<script/redirect/> address)])
                    <handover/>))
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
  able to reach. The supplied `start` event owns the final readiness event,
  so registration and the Aether announcement happen only after its RPC
  listeners are bound.
  ```
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
