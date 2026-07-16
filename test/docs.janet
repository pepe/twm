(use spork/test)

(start-suite "docs")
(assert-docs "../twm/base")
(assert-docs "../twm/app")
(assert-docs "../twm/thicket")
(assert-docs "../twm/sentry")
(assert-docs "../twm/demiurge")
(end-suite)
