(import ./thicket :prefix "")

(setdyn *handler-defines* [:view :conn])
(defdyn *view* "View for handlers")

(defn session/publish
  ```
  Publishes a session from outside the manager, requiring an applied Tree receipt.

  The session is said together with its `owner`, the guardian whose door
  it opens -- by default this symbiont's own, `session/owner`. A tree
  keeping one session for the whole Thicket ignores it.
  ```
  [session &opt owner]
  (def context @{})
  (produce/applied
    [(make-update
       (fn [_ state]
         (put context :tree (state :tree))
         (put context :owner (session/owner state))))])
  (def receipt (:session/new (context :tree) session (or owner (context :owner))))
  (assert (= :applied (get receipt :status)) "Tree did not acknowledge an applied session")
  receipt)

(defn ^session/new
  "Publishes a session asynchronously and runs successors only on applied success."
  [session & after]
  (make-watch
    (producer
      (session/publish session)
      (when (present? after) (produce ;after)))
    "publish session"))

(defn session/settled?
  "Checks exact session equality; an ended session is not an authentication capability."
  [tree session]
  (match (protect (:session/matches tree session))
    [true matches] (truthy? matches)
    false))

(defn ^session/end
  "Ends a session and proceeds only after Tree confirms application."
  [& after]
  (apply ^session/new "" (or after [])))

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
                           :rpc (get-in config
                                        [:mycelium :nodes guarded :rpc])})))
          config)
        (<:- t :spaces (fn [&] spaces))
        (fn [config]
          (def entrances (filter |(get $ :entrance false) (values spaces)))
          (when (not (empty? spaces))
            (assert (= 1 (length entrances))
                    (string "Guardian " sentry " must hold exactly one entrance, found "
                            (length entrances) ".")))
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
  the tree what the Thicket's session is before answering on it again.

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
        [(projection/^refresh [:cap/session] (^space/resume space))]))
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
  (eprin (string name " logout/stand-down-begin\n"))
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

  The shedding belongs here and nowhere else. This is the one moment a
  symbiont stops answering for a place and goes on living, so it is the
  one moment the connections it has already accepted have to be taken
  away from it -- everywhere else the addresses are given up the process
  goes too, and its sockets with it. It runs in the fiber writing the
  handover, which is how the reply being written is the one connection
  spared.
  ```
  [view]
  (when (view :guards)
    (space/let-go (view :space))
    (space/shed (view :space))))

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
  `Max-Age=0` removes a cookie only by matching the name, path and domain
  it was set with, so this has to say exactly what `auth` said and no more
  -- an expiry aimed at a scope nothing was ever set at removes nothing and
  leaves the live cookie sitting beside a second, empty one.

  Waiting on `done` before answering is what makes the reconnection safe.
  The stage the browser comes back to is served by whoever holds the place,
  and if that is still this symbiont it must already know the session ended
  -- otherwise the door reopens on the posture that was just left.
  ```
  [view done sent]
  (def transition (view :transition/logout))
  (http/stream-with
    (merge <handover/>
           (http/cookie "session" "; Max-Age=0; Path=/;"))
    (ev/with-deadline 10 (ev/take done))
    (eprin (string (view :name) " logout/response-ready\n"))
    (:write (dyn :sse-conn) transition)
    (protect (:flush (dyn :sse-conn)))
    (eprin (string (view :name) " logout/transition-written\n"))
    (:give sent true)))

(defn- logout/standdown-after
  "Waits for the logout response before exiting the symbiont."
  [sent]
  (make-watch
    (producer
      (protect (ev/with-deadline 10 (ev/take sent)))
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
  (produce (log "logout-request name=" (view :name)
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
      (^session/end settled)
      # Signal the response before standing down: StandDown exits this
      # manager after closing the dashboard's address.
      (^session/end settled
                    (logout/standdown-after sent))))
  (logout/response view done sent))

(defn- session/?offered
  ```
  Whether `key` is what a request offered under `session`, or among the
  values it offered there.

  Written with a scan rather than a type test because this closure is
  marshalled: the capability is built here, handed to the tree, and sent
  back down the mycelium to whoever holds the place. `gp`'s RPC marshals
  with no dictionary, so a C function reached from inside it cannot cross
  -- `indexed?`, `array?` and `type` each take the tree's connection down
  with them at the moment it answers `:register`. The comparison operator
  survives because the compiler inlines it as an instruction rather than
  looking it up.

  A single value never reaches the loop, and a string that reaches it is
  walked as bytes, which are integers and match no session.
  ```
  [key]
  (fn offered? [offered]
    (var found (= key offered))
    (unless found
      (when offered
        (each value offered
          (when (= key value) (set found true)))))
    found))

(defn =>session/?eq
  ```
  Creates a session check function from a non-empty session `key`.

  What arrives under `session` may be one value or several. Two cookies of
  one name are distinct whenever their domain or path differ, and a
  browser offers every one that matches, together, in the order it likes.
  So the question this asks is whether any of them is this session -- not
  whether the one that happened to arrive last is, which is a question
  about another host's login times.
  ```
  [key]
  # The empty string is the logout sentinel. Janet considers it truthy,
  # so checking only `key` would let an empty Cookie match an ended session.
  (if (present-string? key)
    (=<> :headers "Cookie" "session" (session/?offered key))
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

(defn place/url
  ```
  `path` as the browser must ask for it of the place being answered for.

  A place is either an origin of its own -- its own host, or its own port
  -- or one of several sharing an origin and told apart by a path. Every
  URL in a document is resolved by the browser against the origin, so a
  root-absolute `/content` asks the origin's *root* for it. Where a place
  is its own origin that is the place itself, which is why this was never
  wrong in development, where each door has a port. Where places share an
  origin the root is the entrance's, so a secondary door served its
  Membrane and the Membrane then opened the entrance's stage -- the
  cosymbiont reached, and answered for by somebody else.

  The entrance is the only door carrying a form, a resume or a logout,
  and its address is the origin's root wherever this arrangement is used,
  so those were never wrong. They ask through here so that they stay right
  if the entrance is ever put under a path of its own.

  The `:address` already says which arrangement it is, and every symbiont
  already writes its URLs from its own. A guardian holds several, so it
  reads the one it is answering for now instead of being compiled with a
  single one. The trailing slash is trimmed because `path` brings its own,
  and an address written with one would otherwise ask for `//content`.

  `address` is given explicitly by whatever is built before there is a
  view to read -- a transition is written once per place and kept, not
  rendered per request -- and defaults to the view of the place being
  answered for. An address of nothing yields the bare path, which is what
  this always did.
  ```
  [path &opt address]
  (default address (get (dyn *view*) :address))
  (default address "")
  (string (if (string/has-suffix? "/" address)
            (slice address 0 -2)
            address)
          path))

(defn <form/>
  ```
  Shared sentry login form, offered over Datastar rather than posted.

  A form that posts navigates, and navigating renews the Membrane -- which
  is the one thing a posture change must not do. `__prevent` is Datastar's
  own modifier, so nothing here is a script either.

  Built per request rather than held as a constant, because where it posts
  depends on which door is asking.

  The secret takes focus whenever the form arrives, because typing it is
  the only thing to do here. `autofocus` would not do: the form is patched
  into a document that is already loaded, and a document honours
  `autofocus` once at most, so after a refused secret or a logout the
  form would come back without focus. Datastar's `data-init` runs on
  every patch.
  ```
  []
  [:form {:id "gate" :class "f-col center"
          :data-signals "{secret:''}"
          :data-on:submit__prevent (string "@post('" (place/url "/") "')")}
   [:input {:type "password" :data-bind "secret" :data-init "el.focus()"}]
   [:button [:strong "Use"]]])

(defn- content/into-stage
  ```
  Writes `elements` into the Membrane's stage as the entrance, having
  first put back the entrance's own header.

  Taking `/content` is taking the whole place, and the Membrane in the
  browser may be the other symbiont's -- coming out of a logout it always
  is, because nobody navigated. So the guardian restores its header before
  filling the stage, exactly as the symbiont it guards does on the way in.

  What it writes is wrapped, and the wrapper is the point: it says a
  guardian is standing here, for as long as one is. A door looks nothing
  like the place behind it -- one element centred in an empty stage -- and
  that used to be a stylesheet of its own, named by an element the two
  symbionts exchanged as the place changed hands. A style that follows the
  entrance itself needs no exchanging, and goes when the entrance does.

  The header is optional. A project that gives its guardian none of its
  own has none to put back.
  ```
  [elements]
  (def {:header header} ((dyn :view) :templates))
  (if header (ds/hg/patch header "header" "outer"))
  (ds/hg/patch
    # One element or several. An element names its tag first, so a
    # keyword there is the one and anything else is a sequence of them --
    # true of a tuple of elements as much as an array, which asking after
    # the container was not.
    [:div {:id "entrance"}
     ;(if (keyword? (first elements)) [elements] elements)]
    "#stage" "inner"))

(defn- handover/transition
  ```
  Writes a prebuilt transition and then gives the place up.

  The order is the whole of it. The document has to be on the wire before
  the listener closes, because closing wakes the accepting fiber and can
  take the response with it. The browser then polls the incoming role's
  readiness endpoint before requesting content or navigating. It does
  not infer readiness from the elapsed time since this response.
  ```
  [view guards transition]
  (:write (dyn :sse-conn) transition)
  (protect (:flush (dyn :sse-conn)))
  (handover/after-response view guards))

(defn place/secondary?
  ```
  Whether `place` is a door other than the Thicket's entrance.

  The one distinction that matters about a place. The entrance is where a
  session is granted, so it alone carries a form, a resume and a logout;
  and it is the door a browser is already standing at when the posture
  changes, so its document has to survive the change. Every other door is
  arrived at fresh and asks only whether the grant happened, so its
  document has nothing to survive and is renewed instead.

  Said once because the routes and the transition have to agree about it.
  ```
  [place]
  (not (get place :entrance false)))

(defn- transition/of
  ```
  The transition a project keeps under `key`, settled for `place`.

  A transition is written down rather than performed -- one static string
  of SSE messages, built once and sent verbatim -- so unlike a template it
  is never rendered with a view to hand. The place it reopens has to be
  decided while the place is still in scope, which is here.

  A project that supplies a string is left with it, and keeps the
  root-absolute path it always had.
  ```
  [templates key place]
  (def held (get templates key))
  (if (function? held)
    (held (or (place :address) "") (place :guards))
    held))

(defn ^prepare-view
  "Initializes the shared sentry handler view with project templates."
  [templates]
  (make-event
    {:update
     (fn [_ state]
       # One capability belongs to the Thicket and is held by every view,
       # so a single push must reach all of its places.
       (def cap (>base false))
       # The other places send anyone without a session to the one explicit
       # entrance, where the shared session is granted.
       (def entrance
         (some |(if ($ :entrance) ($ :address))
               (values (get state :spaces {}))))
       (defn view/of [place]
         (merge (select-keys state [:name :secret :key])
                (select-keys place [:guards :public :address :entrance])
                @{:cap/session cap :templates templates :entrance/address entrance
                  # A transition is a constant -- built once and written
                  # verbatim -- so the place it reopens has to be settled
                  # here, where the place is known, rather than per
                  # request. A project that supplies a string instead of a
                  # function keeps the root-absolute path it always had.
                  # Which way in this door hands over is a fact about the
                  # door, not about the handler doing it, and it is the
                  # same fact that decides the routes. Settled here, every
                  # handler goes on writing whatever it finds.
                  :transition/entering
                  (transition/of templates
                                 (if (place/secondary? place)
                                   :transition/new-membrane
                                   :transition/same-membrane)
                                 place)
                  :transition/logout (transition/of templates :transition/logout place)
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
  (def transition (view :transition/entering))
  (def {:guards guards} view)
  (if-let [ck ((view :cap/session) req)]
    (if resume
      (http/stream (content/into-stage (resume guards)))
      (http/stream-with <handover/> (handover/transition view guards transition)))
    (http/stream
      (content/into-stage
        @[(if (function? title) (title (human guards)) title)
          (or form (<form/>))]))))

(defh /continue
  "Wakes the guarded symbiont after a valid dormant sentry session."
  [http/cookies]
  (define :view)
  (def transition (view :transition/entering))
  (def {:guards guards} view)
  (if ((view :cap/session) req)
    (http/stream-with <handover/> (handover/transition view guards transition))
    (http/stream (content/into-stage (<form/>)))))

(defh auth
  ```
  Authenticates a secret offered over Datastar and publishes its session.

  The cookie goes in the head of this very stream. It is the only place it
  can go: once events are flowing the head is gone, and an HttpOnly cookie
  is beyond the reach of anything the browser could be told to do. So the
  session is established, the head carries it, and only then does the
  transition go out.

  It carries no `Domain`, which makes it host-only: the browser offers it
  back to the host that issued it and to no other. A `Domain` widens a
  cookie to that host *and every name beneath it*, so a session issued at
  the apex is presented at every environment standing under it -- and two
  cookies of one name arrive together, of which a server sees whichever it
  happens to keep. Places sharing a host and told apart by path need none
  of that width; they are already the same host.
  ```
  [http/keywordize-body http/json->body]
  (define :view)
  (def {:failure failure :form form} (view :templates))
  (def transition (view :transition/entering))
  # Datastar sends a GET's signals in the query and a POST's in the body.
  # This is a POST, because the secret has no business in a URL.
  (def secret (get body :secret ""))
  (produce (diag "auth-request name=" (view :name)
                 " secret-present=" (truthy? (view :secret))
                 " offered-secret-present=" (present-string? secret)))
  (if-let [sec (view :secret)
           {:key key :guards guards} view
           _ (pwhash/verify sec secret key)]
    (let [sk (derive-from key)]
      (produce (diag "auth-success name=" (view :name)
                     " guards=" guards " session-length=" (length sk)))
      (session/publish sk)
      (http/stream-with
        (merge <handover/>
               (http/cookie "session"
                            (string sk "; Secure; HttpOnly; Path=/;")))
        (handover/transition view guards transition)))
    (do
      (produce (diag "auth-failure name=" (view :name)))
      # A refused secret changes no posture: the door stays held, the
      # Membrane stays put, and the stage is simply told to say so.
      (http/stream
        (content/into-stage @[failure (or form (<form/>))])))))

(defh inhabited
  ```
  Serves the Membrane for a secondary place. There is no secret to offer
  here: the session is granted at the entrance, and this door only asks
  whether it was.
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
  (def transition (view :transition/entering))
  (def {:guards guards :entrance/address entrance} view)
  (if ((view :cap/session) req)
    (http/stream-with <handover/> (handover/transition view guards transition))
    (http/stream (content/into-stage (unauthorized guards entrance)))))

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

  Refusing was the first answer and it was not enough: the tab stopped
  being lied to and went on showing a departed symbiont's document, since
  nothing in it had any reason to ask for anything else. So the stray
  stream is answered as a stream, and what it carries is a way out --
  the same knock the guardian uses when it hands a place over, patched in
  and left to enter the door on its own.

  A redirect status would not do it. Datastar asks with `fetch`, which
  follows a redirect itself and hands the body back to the caller; the
  browser never goes anywhere. Navigating is the document's to do, so it
  has to be told in something the document will run.

  This is posture in a fallback, which is more than a fallback is meant
  to carry. It earns it by being the only line left to a tab whose place
  has gone.
  ```
  [address handler]
  (fn navigations-only [req]
    (if (string/find "datastar=" (or (req :query-string) ""))
      (http/stream
        (ds/hg/patch (<script/redirect/> address) "body" "append"))
      (handler req))))

(defn routes
  ```
  Builds the routes of one living space.

  The entrance is where the shared session is granted, and it alone carries
  the form, the resume and the logout. Every other place the guardian holds
  asks only whether that grant happened.
  ```
  [templates place]
  (if (place/secondary? place)
    @{"/" (http/dispatch {"GET" inhabited})
      "/content" (http/dispatch {"GET" inhabited/content})}
    (merge
      (if (get templates :fallback false)
        @{:not-found (navigations-only
                       (place :address)
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
  each one it stands in for: the tree pushes the Thicket's capability to
  every registered symbiont, and it must find a `:refresh` at each address
  whether the symbiont or its guardian is holding it.
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
