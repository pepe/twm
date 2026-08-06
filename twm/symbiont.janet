(import ./thicket :prefix "")

(defn run
  "Connects peers before announcing a symbiont ready for public handover."
  [config start & before]
  (-> config
      (make-manager on-error)
      (:transact ;before
                 (^connect-peers @[start AetherReady] Exit))
      :await))

(defmacro main
  "Defines a symbiont executable entry point around `run`."
  [config start & before]
  ~(defn main
     "Main entry into a symbiont executable."
     [_ & _args]
     (,run ,config ,start ,;before)
     (,os/exit 0)))
