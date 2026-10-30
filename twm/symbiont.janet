(import ./thicket :prefix "")

(defn run
  "Runs a symbiont lifecycle around its project-specific setup and start events."
  [config start & before]
  (supervisor/arm)
  (-> config
      (make-manager on-error)
      (:transact ;before
                 (^connect-peers start Exit))
      :await))

(defmacro main
  "Defines a symbiont executable entry point around `run`."
  [config start & before]
  ~(defn main
     "Main entry into a symbiont executable."
     [_ & _args]
     (,run ,config ,start ,;before)
     (,os/exit 0)))
