(import ./thicket :prefix "")

(defn demiurge/watch
  "Runs Demiurge and restarts it when project source files change."
  [conf args]
  (def ch (ev/chan 9))
  (def fw (filewatch/new ch))
  (def mp (peg/compile ~{:matcher ,project-files-peg :main (<- :matcher)}))
  (def cmd |(os/spawn ["janet" "-d" "demiurge.janet" ;args] :p))
  (var demiurge (cmd))
  (ev/sleep 0.2)
  (when ((??? {first (?eq "test")}) args)
    (os/proc-wait demiurge)
    (break))
  (def has-client? ((??? {first (?neq "test")}) args))
  (def autorun? (empty? args))
  (var client
    (if has-client?
      (rpc/client ;(server/host-port (conf :rpc))
                  :client (conf :psk))))
  (if autorun? (:run-peers client))
  (filewatch/add fw "./" :last-write :recursive)
  (filewatch/listen fw)
  (forever
    (def e (ev/take ch))
    (when-let [[fnm] (peg/match mp (e :file-name))]
      (eprinf "----------- File %s modified, restarting Demiurge" fnm)
      (if has-client? (:stop-peers client))
      (ev/sleep 0.1)
      (if has-client?
        (do
          (:stop client)
          (os/proc-wait demiurge))
        (os/proc-kill demiurge))
      (ev/sleep 0.2)
      (set demiurge (cmd))
      (ev/sleep 0.2)
      (if has-client?
        (set client
             (rpc/client ;(server/host-port (conf :rpc))
                         :client (conf :psk))))
      (if autorun? (:run-peers client)))))

(defmacro reimport
  "Freshly imports modules into the caller's scope."
  [& modules]
  ~(upscope
     ,;(map (fn [module]
              ~(import ,module :prefix "" :fresh true :export true))
            modules)))

(defmacro reload-store
  "Reloads a Store from the image named by a tree configuration file."
  [conf-file]
  ~(upscope
     (def tree
       (make Store
             :image ((parse (slurp ,conf-file)) :image)))
     (:init tree)))
