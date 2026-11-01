(import jhydro)

# A Yarlyk is the portable warrant CANON describes: a Baskak's word that
# the grounds for one consequence, at one door, were sufficient. It is not
# authorization -- the door it is shown at still decides -- so everything
# here is about whether the warrant is genuine, current and meant for this
# door, and nothing about whether the bearer should be let in.

(def yarlyk/ctx
  ```
  The jhydro signing context of every Yarlyk.

  Eight bytes, as jhydro requires. A signature made under another context
  does not verify under this one, so no other thing a key signs can be
  presented as a warrant.
  ```
  "yarlyk01")

(def yarlyk/version "The one payload version this code issues and accepts." 1)

(def yarlyk/kind "The one kind of warrant there is so far." :yarlyk/admission)

(def yarlyk/skew
  ```
  Seconds a warrant may be dated ahead of the verifier's clock.

  Issuer and door share a box today, so the clocks agree to the second; a
  little slack keeps a warrant issued at the end of one second from being
  refused at the start of the same one elsewhere.
  ```
  5)

(defn yarlyk/keygen
  "A fresh signing keypair for a Baskak, as strings: `{:public-key :secret-key}`."
  []
  (def {:public-key pk :secret-key sk} (jhydro/sign/keygen))
  {:public-key (string pk) :secret-key (string sk)})

(defn yarlyk/serial
  "A fresh serial: 16 random bytes in hex, the nonce a door remembers."
  []
  (string/join (map |(string/format "%02x" $) (jhydro/random/buf 16))))

(defn yarlyk/issue
  ```
  Signs `claims` as a Yarlyk valid for `ttl` seconds from `now`.

  The claims are the Baskak's: who, which door, which capability, on
  which grounds. The version, kind, serial and validity are added here so
  no issuer writes them differently. The payload is the claims written as
  JDN, and those exact bytes are what is signed and what travels: the
  verifier checks the signature over the bytes it received before it reads
  a single field, so there is no canonical form to agree on.
  ```
  [claims secret-key ttl &opt now]
  (default now (os/time))
  (def payload
    (string/format "%j"
                   (table/to-struct
                     (merge-into @{} claims
                                 {:v yarlyk/version
                                  :kind yarlyk/kind
                                  :serial (yarlyk/serial)
                                  :issued now
                                  :expires (+ now ttl)}))))
  {:yarlyk payload
   :signature (string (jhydro/sign/create payload yarlyk/ctx secret-key))})

(defn- signed-by?
  "Whether `signature` over `payload` verifies under any of `issuers`."
  [payload signature issuers]
  (some (fn [pk]
          (match (protect (jhydro/sign/verify signature payload yarlyk/ctx pk))
            [true ok] ok
            false))
        issuers))

(defn- payload/read
  "The one struct `payload` holds, or nil."
  [payload]
  (match (protect (parse-all payload))
    [true forms] (if (and (= 1 (length forms)) (struct? (first forms)))
                   (first forms))
    nil))

(defn yarlyk/forget
  "Drops every remembered serial whose warrant has expired by `now`."
  [seen now]
  (eachp [serial expires] seen
    (when (< expires now) (put seen serial nil)))
  seen)

(defn yarlyk/verify
  ```
  Checks a Yarlyk presented at a door, and remembers its serial.

  `wire` is what was presented, `{:yarlyk :signature}`. `door` says what
  this door accepts:

  - `:issuers`, the public keys of the Baskaks it trusts;
  - `:door`, its own id, which the warrant must name;
  - `:consequence`, the one consequence it grants;
  - `:max-ttl`, the longest validity it accepts, however the issuer set it;
  - `:started`, when it began answering -- a warrant issued before that
    may already have been used against a door that has since forgotten;
  - `:seen`, a table of serials already accepted, kept by the caller.

  Returns `[:ok claims]`, or `[:refused reason]`. The order is the point:
  nothing of the payload is believed until the signature over its bytes
  holds, and the serial is remembered only once everything else does, so
  a refused warrant cannot use up a good one's serial.
  ```
  [wire door &opt now]
  (default now (os/time))
  (def {:issuers issuers :door id :consequence consequence
        :max-ttl max-ttl :started started :seen seen} door)
  (def payload (if (dictionary? wire) (get wire :yarlyk)))
  (def signature (if (dictionary? wire) (get wire :signature)))
  (yarlyk/forget seen now)
  (def claims
    (if (and (bytes? payload) (bytes? signature))
      (if (signed-by? payload signature issuers) (payload/read payload) :signature)))
  (cond
    (nil? claims) [:refused :malformed]
    (= :signature claims) [:refused :signature]
    (not= yarlyk/version (claims :v)) [:refused :version]
    (not= yarlyk/kind (claims :kind)) [:refused :kind]
    (not (and (number? (claims :issued)) (number? (claims :expires))
              (bytes? (claims :serial))))
    [:refused :malformed]
    (not= id (claims :door)) [:refused :door]
    (not= consequence (claims :consequence)) [:refused :consequence]
    (> (claims :issued) (+ now yarlyk/skew)) [:refused :not-yet]
    (> now (claims :expires)) [:refused :expired]
    (> (- (claims :expires) (claims :issued)) max-ttl) [:refused :ttl]
    (< (claims :issued) started) [:refused :before-start]
    (get seen (claims :serial)) [:refused :replayed]
    (do
      (put seen (claims :serial) (claims :expires))
      [:ok claims])))

(defn door/psk
  ```
  The key a caller in thicket `from` and the door `door` of thicket `to`
  speak with: the parent's key hashed with the three names.

  Derived the way `subthicket/psk` derives a subthicket's, and for the
  same reasons: the key goes into the hashed bytes, ahead of the names,
  and zero bytes keep one triple from reading as another. Each door knows
  only its own, so a caller holding one cannot knock at any other.
  ```
  [psk from to door]
  (string (jhydro/hash/hash 32 (string psk "\0" from "\0" to "\0" door)
                            "twmcross")))
