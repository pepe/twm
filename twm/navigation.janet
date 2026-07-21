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
                (<:= t (=> =>membrane :rpc |{:membrane/rpc $}))
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
        (<:- t :tenant (=> :symbionts
                           (fn [b] (b (array/pop c))) :tenant))
        (>base t))))
