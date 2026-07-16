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
  "Navigation to sentry initial state"
  [sentry]
  (let [c @[] t @{}
        =>guards (=> :symbionts sentry :guards)]
    (=> (>if =>guards
             (=> (<- c =>guards)
                 (<:- t :tenant (>or (=> :symbionts |(get $ (array/peek c)) :tenant)
                                     (fn [&] (array/peek c))))
                 (<:= t (=>mycelium/peers
                          (=> :mycelium :nodes |(get $ (array/peek c)))))
                 (<:= t (=> :mycelium :nodes |(get $ (array/peek c))))
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
  "Handles logout"
  []
  (produce (^session/new "") SpawnExit)
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
