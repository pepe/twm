# twm — Thicket Web Mind

The environment organism of a Thicket: the Symbiont scaffolding every
Flower grows on, itself grown on the [gp](https://git.sr.ht/~pepe/gp)
substrate. Gestated inside the metabolon Thicket and shaped by the needs
of four running Flowers (metabolon, interstudy, pacts, bow) before its
birth as this repository.

## Modules

- `twm/base` — the effect discipline. Logging, journaling, and
  stacktraces are lawful effects, never ambient side effects. Re-exports
  the substrate (gp) and spork surface the upper modules stand on.
- `twm/app` — Symbiont machinery. Handlers (`defh`) and RPC functions
  (`defr`) with declared dynamics, HTTP and RPC servers as producers,
  store lifecycle (`PrepareStore`, `SeedStore`), heart-beat, aether
  spawn/occupation, datastar helpers, test validators.
- `twm/thicket` — the Mycelium fabric. Peer connection and registration,
  Thicket session capability saving, Tree projection refresh
  (`^tree/refresh-view`), and mycelium navigations.
- `twm/sentry` — the guardian. Shapes session Capabilities
  (`=>session/?eq`), gates requests on the bearer's cap (`check-session`,
  `session/check-with`), handles `/logout` (303), navigates sentry
  initial state.
- `twm/demiurge` — the lifecycle authority. Births, supervises,
  heart-checks, restarts, builds, deploys, and releases Symbionts; runs
  test suites against a freshly born Tree. Owns lifecycle truth, never
  business truth. Project specifics reach it through state
  (`:config`, `:nav/symbiont`), never through imports.

## Conventions

A consuming project imports `twm/...` (installed) for the organism and
`gp/...` for the substrate — the two dependency kinds never look alike.
A Tree born onto an empty store endows itself from its configured
`:seed`. Sessions are granted (by the Demiurge at spawn, or by the Tree
at registration) and borne as `:cap/session` — a symbiont verifies its
cap; it never reads the registry. A session belongs to the guardian whose
entrance granted it, and every call that publishes or reads one names
that guardian (`session/owner`), so a Tree may keep one per door; a Tree
keeping one for the whole Thicket ignores the name.

## The Shadow is not the Tree

This library and this README are a projection of what the running
implementations enact. They carry no authority over the Thicket Web Mind
canon, which lives at [pan.earth](https://pan.earth) and alone decides
what TWM is. Everything the canon holds open, negative, or in tension is
deliberately absent here — it lives only in the Tree.
