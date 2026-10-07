# twm — Thicket Web Mind

[![builds.sr.ht status](https://builds.sr.ht/~pepe/twm.svg)](https://builds.sr.ht/~pepe/twm)
[![GitHub Actions](https://github.com/pepe/twm/actions/workflows/test.yml/badge.svg)](https://github.com/pepe/twm/actions/workflows/test.yml)

The environment organism of a Thicket: the Symbiont scaffolding every
Flower grows on, itself grown on the [gp](https://git.sr.ht/~pepe/gp)
substrate. Gestated inside the metabolon Thicket and shaped by the needs
of four running Flowers (metabolon, interstudy, pacts, bow) before its
birth as this repository.

twm is at 0.x, and its API still moves between minor versions. If you
depend on it, pin a release tag.

Development happens at [git.sr.ht/~pepe/twm](https://git.sr.ht/~pepe/twm).
[github.com/pepe/twm](https://github.com/pepe/twm) is a mirror, with issues
and pull requests turned off; send patches and reports to <pe@pan.earth>.

## Requirements

- Janet with the event-loop fix for cancelled producers, "Unregister stream
  from EV upon closure" (#1770), released in v1.42.0. CI builds Janet's
  master branch.
- `spork`, `jhydro`, and gp 0.5.0 or later, which `janet-pm deps` installs.
- For gp's native modules, a C and a C++17 compiler: MSVC on Windows, GCC
  or Clang elsewhere. twm itself is Janet only.

## Installing

```sh
git clone https://git.sr.ht/~pepe/twm
cd twm
janet-pm deps
janet-pm install
```

## Modules

The five a Thicket is built from:

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

And the ones they stand on:

- `twm/tree` — the Tree's side: registering and deregistering peers,
  saving and granting sessions, and its own `run` and `main`.
- `twm/symbiont` — `run` and `main` around a symbiont's setup and start
  events.
- `twm/guarded` — what a guarded symbiont owes the Demiurge's idle
  timeout: counting its use (`^activity`, `session/checker-with`,
  `/watching`), reporting it to the ping (`-:ping/active`), and leaving
  when stopped (`stop/guarded`), telling its live streams first.
- `twm/schema` — the schemas a configuration is checked against: peers,
  the Tree, sentries, symbionts, mycelium, membrane, and deployment.
- `twm/navigation` — navigations into a symbiont's mycelium and membrane
  configuration.
- `twm/lifecycle` — serializable peer intent and generation identity.
  Process handles stay with the Demiurge's observer.
- `twm/projection` — installs Tree snapshots atomically, never moving a
  revision backwards, and coalesces refreshes.
- `twm/delivery` — coalesced delivery of invalidations to peers; the Tree
  never waits for a listener.
- `twm/subscription` — durable, coalescing subscriptions for live
  transports.
- `twm/readiness` — the readiness gate a place opens once its projection
  is installed. It describes readiness, not authentication.
- `twm/handover` — the browser-side waiter that follows a place through a
  listener handover.
- `twm/operation` — detached maintenance operations, one at a time, with
  receipts.
- `twm/artifact` — build artifact identity: content digests, provenance
  records, and verified installs.
- `twm/dev` — watchers that restart or re-test a project's Demiurge when
  its sources change.

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

[`CANON.md`](CANON.md) is the working canon: a candidate text under
active cultivation, as its Status section says.

## Development

Work in a local Janet tree, which git ignores as `dev`:

```sh
janet-pm env dev
. dev/bin/activate      # dev\bin\activate.ps1 in PowerShell
janet-pm deps
janet-pm install
janet-pm test
```

Tests import twm from the working tree (`../twm/...`) and gp, spork, and
jhydro from the installed tree. `janet-pm test` still wants twm installed
first. A single file runs from the repository root with
`janet test/demiurge.janet`.

CI runs on [builds.sr.ht](https://builds.sr.ht/~pepe/twm) under Alpine, and
on GitHub Actions under Linux, macOS, and Windows.

## License

MIT; see [LICENSE](LICENSE).
