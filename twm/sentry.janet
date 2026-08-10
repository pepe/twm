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
  # Standing down is leaving, and leaving is saying so to the peers this
  # symbiont registered with. Without it the tree keeps a client to a
  # process that has gone, and pushes into it long afterwards.
  [ClosePeers (^aether/left name) Exit])

(defn- logout/settled
  "Returns an event that wakes a waiting logout response."
  [done]
  (make-effect
    (fn [_ _ _]
      (:give done true))
    "logout settled"))

(defn- handover/space
  ```
  Releases only a guarded membrane space, never the sentry itself.

  The handover response must have its redirect window before this runs.
  Vacating the listener wakes its accepting fiber; doing that while the
  response is still being written can close the request before its headers
  leave the sentry.
  ```
  [view]
  (when (view :guards)
    (space/let-go (view :space))))

(defn- handover/after-response
  "Releases and spawns only after a sentry response has been written."
  [view guards]
  (handover/space view)
  (produce (^aether/spawn guards "") (^place/leave guards)))

(def- <handover/>
  ```
  Header ending the connection that carried a handover.

  A listener can be closed and the connections it accepted go on living --
  `space/let-go` depends on exactly that, so the answer still reaches
  whoever asked. The cost is that the browser holds a keep-alive socket to
  the guardian, and the beat's request for `/content` would travel back
  down it to a symbiont that has just stepped out of the door. It would be
  answered, too: a session exists by then, so the guardian would offer the
  visitor the way in all over again, while the symbiont that has taken the
  place stands behind a door nobody knocks on.

  The connection has to end with the transition. Then the beat opens a new
  one, and a new one reaches whoever is listening now.
  ```
  {"Connection" "close"})

(defn- logout/response
  ```
  Streams the logout transition, and only once logout has settled on Tree.

  The cookie is dropped in the head, before the first event: the session it
  names is already dead server-side, and a browser still holding it would
  spend the reconnection presenting a key to a lock that has been changed.
  `Max-Age=0` has to repeat the name, path and domain it was set with, or
  it removes nothing and leaves a second cookie beside the first.

  Waiting on `done` before answering is what makes the reconnection safe.
  The stage the browser comes back to is served by whoever holds the place,
  and if that is still this symbiont it must already know the session ended
  -- otherwise the door reopens on the posture that was just left.
  ```
  [view done sent]
  (def transition (view :transition/logout))
  (def {:cookie-host cookie-host} view)
  (http/stream-with
    (merge <handover/>
           (http/cookie "session"
                        (string "; Max-Age=0; Path=/; Domain=" cookie-host ";")))
    (ev/take done)
    (:write (dyn :sse-conn) transition)
    (protect (:flush (dyn :sse-conn)))
    (:give sent true)))

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
                 " guarded=" (truthy? (view :guards))
                 " own-space=" (truthy? (view :space))
                 " session-cap=" (truthy? (view :cap/session))))
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
  (logout/response view done sent))

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
                     " cookie-present=" (truthy? (get-in req [:headers "Cookie" "session"]))
                     " cap-present=" (truthy? (view :cap/session))))
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
  ```
  Shared sentry login form, offered over Datastar rather than posted.

  A form that posts navigates, and navigating renews the Membrane -- which
  is the one thing a posture change must not do. `__prevent` is Datastar's
  own modifier, so nothing here is a script either.
  ```
  [:form {:id "gate" :class "f-col center"
          :data-signals "{secret:''}"
          :data-on:submit__prevent "@post('/')"}
   [:input {:type "password" :data-bind "secret"}]
   [:button [:strong "Use"]]])

(defn- content/into-stage
  ```
  Writes `elements` into the Membrane's stage, having first put back the
  entrance's own furniture.

  Taking `/content` is taking the whole place, and the Membrane in the
  browser may be the other symbiont's -- coming out of a logout it always
  is, because nobody navigated. So the guardian restores its skin and its
  header before filling the stage, exactly as the symbiont it guards does
  on the way in. Without it the entrance is rendered wearing the
  dashboard's styling, which has no notion of centring a door.

  Both are optional. A project that gives its guardian no furniture of its
  own has none to put back.
  ```
  [elements]
  (def {:skin skin :header header} ((dyn :view) :templates))
  (if skin (ds/hg/patch skin "#skin" "outer"))
  (if header (ds/hg/patch header "header" "outer"))
  (ds/hg/patch elements "#stage" "inner"))

(defn- handover/transition
  ```
  Writes a prebuilt transition and then gives the place up.

  The order is the whole of it. The document has to be on the wire before
  the listener closes, because closing wakes the accepting fiber and can
  take the response with it; and the stream has to end after, because the
  beat only starts counting once the browser sees the stream finish.

  What the beat is counting is this handover: by the time it reopens
  `/content`, the door is meant to be answered by whoever is rising into
  it. Nothing here waits for that to be true -- the beat is a constant,
  and a boot slower than it will be met by a door still changing hands.
  ```
  [view guards transition]
  (:write (dyn :sse-conn) transition)
  (protect (:flush (dyn :sse-conn)))
  (handover/after-response view guards))

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
                  :transition/login (get templates :transition/login)
                  :transition/logout (get templates :transition/logout)
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
  ```
  Serves the Membrane.

  It says nothing about who is standing in the door. The Membrane is the
  same document whether a session exists or not -- what differs is what
  `/content` streams into it, and that is asked separately, a moment later.
  Deciding it here would put the posture in the one document that has to
  survive posture changes.
  ```
  [http/cookies]
  (define :view)
  (def {:membrane membrane} (view :templates))
  (membrane/resp (membrane)))

(defh /content
  ```
  Streams the sentry's posture into the Membrane's stage.

  Three of them: no session and the door asks for a secret; a session and a
  dormant symbiont, and the door offers to wake it; a session and nothing
  dormant, and the door has no business being held at all -- the transition
  goes out and the place is handed over.
  ```
  [http/cookies]
  (define :view)
  (def {:title title :form form :resume resume} (view :templates))
  (def transition (view :transition/login))
  (def {:guards guards} view)
  (if-let [ck ((view :cap/session) req)]
    (if resume
      (http/stream (content/into-stage (resume guards)))
      (http/stream-with <handover/> (handover/transition view guards transition)))
    (http/stream
      (content/into-stage
        @[(if (function? title) (title (human guards)) title)
          (or form <form/>)]))))

(defh /continue
  "Wakes the guarded symbiont after a valid dormant sentry session."
  [http/cookies]
  (define :view)
  (def transition (view :transition/login))
  (def {:guards guards} view)
  (if ((view :cap/session) req)
    (http/stream-with <handover/> (handover/transition view guards transition))
    (http/stream (content/into-stage <form/>))))

(defh auth
  ```
  Authenticates a secret offered over Datastar and publishes its session.

  The cookie goes in the head of this very stream. It is the only place it
  can go: once events are flowing the head is gone, and an HttpOnly cookie
  is beyond the reach of anything the browser could be told to do. So the
  session is established, the head carries it, and only then does the
  transition go out.
  ```
  [http/keywordize-body http/json->body]
  (define :view)
  (def {:failure failure :form form} (view :templates))
  (def transition (view :transition/login))
  # Datastar sends a GET's signals in the query and a POST's in the body.
  # This is a POST, because the secret has no business in a URL.
  (def secret (get body :secret ""))
  (produce (diag "auth-request name=" (view :name)
                 " secret-present=" (truthy? (view :secret))
                 " offered-secret-present=" (present-string? secret)))
  (if-let [sec (view :secret)
           {:cookie-host cookie-host :key key :guards guards} view
           _ (pwhash/verify sec secret key)]
    (let [sk (derive-from key)]
      (produce (diag "auth-success name=" (view :name)
                     " guards=" guards " cookie-host=" cookie-host
                     " session-length=" (length sk)))
      (http/stream-with
        (merge <handover/>
               (http/cookie "session"
                            (string sk "; Secure; HttpOnly; Path=/; Domain="
                                    cookie-host ";")))
        (produce (^session/new sk))
        (handover/transition view guards transition)))
    (do
      (produce (diag "auth-failure name=" (view :name)))
      # A refused secret changes no posture: the door stays held, the
      # Membrane stays put, and the stage is simply told to say so.
      (http/stream
        (content/into-stage @[failure (or form <form/>)])))))

(defh inhabited
  ```
  Serves the Membrane for a place the guardian holds for a symbiont other
  than the tenant's own. There is no secret to offer here: the session is
  granted at the tenant's door, and this door only asks whether it was.
  ```
  [http/cookies]
  (define :view)
  (def {:membrane membrane} (view :templates))
  (membrane/resp (membrane)))

(defh inhabited/content
  ```
  Streams the posture of a place held for another symbiont. With a session
  the place is handed back; without one there is nowhere here to earn it,
  so the stage says where to go instead.
  ```
  [http/cookies]
  (define :view)
  (def {:unauthorized unauthorized} (view :templates))
  (def transition (view :transition/login))
  (def {:guards guards :tenant/address home} view)
  (if ((view :cap/session) req)
    (http/stream-with <handover/> (handover/transition view guards transition))
    (http/stream (content/into-stage (unauthorized guards home)))))

(defn- navigations-only
  ```
  Wraps a fallback so it answers navigations and refuses stream requests.

  A fallback that serves the Membrane for every unrouted path is right for
  a visitor arriving at an address nobody routed -- that is what it is
  for. It is wrong for the endpoints belonging to the symbiont this
  guardian stands in for. When that symbiont goes, the browser holding its
  document does not: it goes on asking for the streams that document
  opened, `/totals` and the rest, and the guardian has no such routes. So
  every one of them fell to the fallback and was answered with an HTML
  document under a 200. Datastar asked for events and was handed a page,
  over and over, and the tab quietly came apart.

  Datastar says who it is. Its signals ride in a `datastar` query
  parameter, so a request carrying one is not a navigation and must not be
  given a navigation's answer. Read off the raw query string rather than
  the parsed parameters, which depend on a middleware being in the chain.

  Refusing is the whole of it: the stale tab stops being lied to and needs
  a reload. Answering it with a stream that patches the entrance back in
  would let such a tab heal itself, and would put posture into a fallback,
  which is a larger thing than this.
  ```
  [handler]
  (fn navigations-only [req]
    (if (string/find "datastar=" (or (req :query-string) ""))
      (http/not-found)
      (handler req))))

(defn routes
  ```
  Builds the routes of one living space.

  The tenant's own place is where a session is granted, and it alone
  carries the form, the resume and the logout. Every other place the
  guardian holds asks only whether that grant happened.
  ```
  [templates place]
  (if (not= (place :guards) (place :tenant))
    @{"/" (http/dispatch {"GET" inhabited})
      "/content" (http/dispatch {"GET" inhabited/content})}
    (merge
      (if (get templates :fallback false)
        @{:not-found (navigations-only
                       (http/dispatch {"GET" index "POST" auth}))}
        @{"/" (http/dispatch {"GET" index "POST" auth})})
      # `/content` is the door's one moving part. Every posture the sentry
      # can be in is streamed through it, and every transition ends by
      # asking for it again -- of whoever holds the place by then.
      @{"/content" (http/dispatch {"GET" /content})
        "/continue" (http/dispatch {"GET" /continue})
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
        # A guardian answers on the address of the place it holds, so the
        # stylesheet the Membrane asks for is asked of whoever is standing
        # there. Refusing to serve it was tenable while the sentry's pages
        # were self-contained; sharing one Membrane, it would mean the door
        # loses its styling exactly while the guardian holds it -- or else
        # carries every asset inlined, which is what it was doing.
        #
        # Serving statics means `os/stat`, so a project that wants this must
        # grant its guardian `:fs`, widening the sandbox of the one component
        # facing the world before anyone has authenticated. That is the trade
        # and it is the project's to make: the place's own public path is
        # already inherited, and it is served when there is one.
        (put space :static (truthy? (space :public))))
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

  The doors open after the peers are connected, never before. A guardian
  that binds first is answering the world while it still has no tree: the
  first visitor's secret is accepted and then published through a client
  that has been made and never opened, which fails as an unknown method
  far from here. It is a narrow window on a listening tree and a wide one
  wherever a refused connection is slow to be refused, and it is
  reachable by nothing more unusual than typing quickly. Every other
  symbiont already raises its HTTP inside its start event, which is on
  this side of the connecting -- the guardian was the one raising it
  outside.
  ```
  [config templates rpc-funcs start & before]
  (-> config
      (make-manager on-error)
      (:transact ;before
                 (^prepare-view templates)
                 (^assemble templates rpc-funcs)
                 (^connect-peers [HTTP start] Exit))
      :await))

(defmacro main
  "Defines a sentry executable entry point around `run`."
  [config templates rpc-funcs start & before]
  ~(defn main
     "Main entry into a sentry executable."
     [_ & _args]
     (,run ,config ,templates ,rpc-funcs ,start ,;before)
     (,os/exit 0)))
