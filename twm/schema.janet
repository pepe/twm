(import ./base :prefix "")

(def?! sha string? (?long 40))

(def?! ok (?eq :ok))

(def?! hash string? (?long 32))

(def?! peer present? keyword?)

(def?! url
  present-string?
  (?matches-peg '(* (to ":") ":" (some :d) -1)))

(def?! hash-dictionary
  dictionary?
  {keys (>?? all hash?)})

(def?! peer/dictionary
  dictionary?
  {keys (>?? all peer?)})

(def?! config/caps
  {:caps (?optional (>?? all keyword?))})

(def?! config/tenant
  {:tenant (?optional peer?)})

(def?! config/runtime
  {:debug boolean?
   :log boolean?
   :diagnostic (?optional boolean?)})

(def?! config/deploy
  dictionary?
  {:host present-string?
   :build-path (?optional present-string?)
   :release-path present-string?
   :data-path (?optional present-string?)
   :env (?optional present-string?)
   :repo (?optional present-string?)
   :dry (?optional boolean?)
   :debug (?optional boolean?)
   :log (?optional boolean?)})

(def?! config/persisted
  {:image (?optional present-string?)})

(def?! config/named
  {:name (?optional keyword?)})

(def?! config/entry
  {:entry present-string?})

(def?! config/tree
  dictionary?
  config/entry?
  config/persisted?
  config/caps?
  {:seed (?optional present-string?)})

(def?! config/avatar
  dictionary?
  config/entry?
  config/persisted?
  config/caps?
  config/tenant?
  {:guarded-by (?optional peer?)
   :timeout (?optional number?)})

(def?! config/sentry
  dictionary?
  config/entry?
  config/caps?
  config/tenant?
  {:secret (?optional present-string?)
   :key (?optional present-string?)})

(def?! config/command
  config/avatar?)

(def?! config/demiurge
  dictionary?
  config/entry?
  config/caps?
  {:builder boolean?
   :autostart (>?? all peer?)
   :builds (>?? all peer?)
   :timeout (?optional number?)})

(def?! config/symbiont
  (>check-all some config/demiurge? config/tree? config/avatar?
              config/sentry? config/command?))

(def?! config/symbionts
  dictionary?
  {keys (>?? all keyword)
   values (>?? all config/symbiont?)})

(def?! config/mycelium/node
  dictionary?
  {:rpc url?
   :peers (?optional (??? tuple? (>?? all peer?)))
   :key (?optional present-string?)})

(def?! config/mycelium/nodes
  dictionary?
  {keys (>?? all keyword)
   values (>?? all config/mycelium/node?)})

(def?! config/mycelium
  dictionary?
  {:psk present-string?
   :nodes config/mycelium/nodes?})

(def?! config/membrane/rpc-node
  dictionary?
  {:rpc url?
   :key (?optional present-string?)})

(def?! config/membrane/http-node
  dictionary?
  {:http url?
   :address (?optional present-string?)
   :neighbors (?optional (>?? all peer?))
   :static (?optional boolean?)
   :public (?optional present-string?)}
  (>if (=> :static true?)
       (=> :public (>assert present-string?))))

(def?! config/membrane/nodes
  dictionary?
  {keys (>?? all keyword)
   values (>?? all (>check-all some config/membrane/rpc-node?
                               config/membrane/http-node?))})

(def?! config/membrane
  dictionary?
  {:nodes config/membrane/nodes?})

(def?! config
  dictionary?
  {:name present-string?
   :deploy config/deploy?
   :runtime config/runtime?
   :symbionts config/symbionts?
   :mycelium config/mycelium?
   :membrane config/membrane?
   :handles (?optional dictionary?)})

(defn load-config
  "Loads the compile-time thicket configuration."
  [&opt file]
  (parse (slurp (or file (os/getenv "CONF" "conf.jdn")))))
