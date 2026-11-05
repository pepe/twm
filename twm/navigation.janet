(import ./thicket :prefix "" :export true)
(import ./sentry :as sentry)
(use spork/path)
(use gp/data/navigation)

(defn =>symbiont/mycelium
  "Navigation to a symbiont's mycelium configuration."
  [symbiont]
  (let [t @{}
        =>mycelium (=>mycelium/node symbiont)]
    (=> (<:- t :psk (=> :mycelium :psk))
        (>if =>mycelium
             (=>
               (<:= t =>mycelium)
               (<:= t (=>mycelium/peers =>mycelium))))
        (>base t))))

(defn =>symbiont/membrane
  "Navigation to a symbiont's membrane configuration."
  [symbiont]
  (let [c @[]
        t @{}
        =>membrane (=> :membrane :nodes symbiont)
        =>neighbors (=> =>membrane :neighbors)]
    (=>
      (<:- t :build-path (=> :deploy :build-path))
      (>if =>membrane
           (>if (=> =>membrane :rpc)
                # A guardian's door is its own membrane rpc node, with the
                # key of the one relation it answers.
                (<:= t (=> =>membrane |{:membrane/rpc ($ :rpc)
                                         :membrane/key ($ :key)}))
                (=> (<:= t =>membrane)
                    (>if (=> =>neighbors present?)
                         (=> (<- c =>neighbors)
                             (<:= t (=> :membrane :nodes
                                        |(tabseq [i :in (array/pop c)]
                                           i ((=> i :address) $)))))))))
      (>if (=> =>membrane :public)
           (<:= t (=> =>membrane :public
                      |{:public (posix/join (t :build-path) $)})))
      (>base t)
      (>put :build-path nil))))

(defn =>symbiont/crossings
  ```
  Navigation to the doors of other Thickets a symbiont may cross to.

  Only a symbiont saying `:crosses true` is given them. Each is a
  membrane rpc node naming the `:door` it reaches -- `<thicket>/<guardian>`
  -- with that relation's `:key`, the `:address` of the place the door
  opens and, when given, the `:title` its Thicket goes by and the
  `:short` name it is called by where room is scarce; the symbiont gets
  them keyed by the door. A Thicket speaks to
  another only through its Membrane, so the address and the key are in the
  caller's own configuration, and nothing about the caller is in the
  other's.
  ```
  [symbiont]
  (fn [config]
    (if (get-in config [:symbionts symbiont :crosses])
      {:crossings
       (tabseq [node :in (values (get-in config [:membrane :nodes] {}))
                :when (get node :door)]
         (node :door) {:rpc (node :rpc) :key (node :key) :title (node :title)
                       :short (node :short) :address (node :address)})}
      {})))

(defn =>guarded/owner
  ```
  Navigation to whose sessions open a guarded symbiont, when its guardian
  holds several identities: its own, as the guardian's place for it is
  owned by that person. Any other symbiont is left to `session/owner`.
  ```
  [symbiont]
  (fn [config]
    (def guardian (get-in config [:symbionts symbiont :guarded-by]))
    (if (get-in config [:symbionts guardian :identities symbiont])
      {:session/owner symbiont}
      {})))

(defn =>symbiont/image
  "Navigation to a symbiont's persisted image."
  [symbiont]
  (let [c @[]
        =>image (=> :symbionts symbiont :image)]
    (>if =>image
         (=> (<- c (=> :deploy :data-path))
             (=> =>image
                 |{:image (posix/join (array/pop c) $)}))
         (>base {}))))

(defn =>demiurge/initial-state
  "Navigation to extract demiurge configuration from the thicket-wide config."
  [symbiont]
  (let [c @[]
        t @{}
        =>builds (=> :symbionts symbiont :builds)]
    (if ((?eq :demiurge) symbiont)
      (>if =>builds
           (=>
             (<:= t (=> :deploy))
             (<:- t :entries
                  (=> (<- c =>builds)
                      (>if (=> :handles)
                           (<- c (=> :handles keys)))
                      |(tabseq [p :in (flatten c)]
                         p ((>or (=> :symbionts p :entry)
                                 (=> :handles p :entry)) $))))
             (>base t))
           (>base {}))
      (>base {}))))

(defn =>symbiont/initial-state
  "Navigation to extract one symbiont's initial state."
  [symbiont]
  (let [t @{:name symbiont}]
    (=> (<:- t :thicket (=> :name))
        (<:= t (=> :symbionts symbiont))
        (<:= t (=> :runtime))
        (<:= t (=>symbiont/mycelium symbiont))
        (<:= t (=>symbiont/membrane symbiont))
        (<:= t (=>symbiont/image symbiont))
        (<:= t (=>symbiont/crossings symbiont))
        (<:= t (=>guarded/owner symbiont))
        (<:= t (=>demiurge/initial-state symbiont))
        (<:= t (sentry/=>sentry/initial-state symbiont))
        (>base t))))

(defn =>handle/initial-state
  "Navigation to extract a handle configuration."
  [handle]
  (let [c @[]
        t @{:name handle}]
    (=> (<:- t :thicket (=> :name))
        (<:- t :psk (=> :mycelium :psk))
        (<:= t (=> :handles handle))
         (<- c (=> :handles handle :reaches))
         (<:- t :rpc (=> :membrane :nodes
                         (fn [b] (b (array/peek c))) :rpc))
         (>base t))))
