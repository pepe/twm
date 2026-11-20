# Decision ledger

One entry per decision, newest last, except D-001, which says how this ledger is rooted. IDs are stable and never reused.
Status values: `proposed`, `accepted`, `superseded`, `withdrawn`.
A decision of a dependent is named by repository and ID (`metabolon D-005`); it binds there, not here.

D-002 to D-004 were extracted on 2026-11-20 from `README.md` and the history by Claude Opus 5.5, and confirmed by Josef the same day.

| ID | Date | Decision | Decided by | Grounds / source | Status | Where |
|---|---|---|---|---|---|---|
| D-001 | 2026-11-20 | twm is governed on its own, not under tots: tots and its tenants depend on twm, and twm on none of them. Its rules restate what it shares with tots' instead of inheriting them | Josef (proposed by Claude) | the dependency runs one way; inheriting from a dependent would turn it | accepted | `AGENTS.md` |
| D-002 | 2026-08-16 | The Canon is published with the library: it lives in this repository as `CANON.md`, and every release tag carries its state | Josef | `2c0f221` "Add current Canon" | accepted | `CANON.md` |
| D-003 | 2026-10-01 | Development happens on sr.ht; GitHub is a mirror with issues and pull requests turned off; patches and reports go by mail | Josef | `README.md` | accepted | `f7e0398` |
| D-004 | 2026-10-01 | twm is at 0.x, and its API may move between minor versions; a dependent pins a release tag | Josef | `README.md` | accepted | `f7e0398` |
| D-006 | 2026-11-20 | Governance brings no business value of its own, so it is kept as smooth as possible: the keeper is not asked to commit, clean up or repeat what an assistant can do | Josef | conversation with Claude, 2026-11-20 | accepted | `ledger.md` |
| D-007 | 2026-11-20 | Work moves through four roles, which the keeper assigns to participants, people or models: the analyst investigates the need, tests its assumptions, names the decisions the keeper must make, and writes the brief; the planner checks the brief against the sources and proposes the approach with its validation; the programmer carries out the plan, verifies it, and reports deviations and what remains; the keeper decides purpose and scope, accepts decisions, and merges and releases. A role that finds a problem upstream returns the question to the role that owns it (purpose and scope to the keeper, the brief to the analyst) and does not rewrite the brief or widen the work. The analyst checks the finished change against the need; technical review checks its correctness | proposed by Claude and another assistant | conversation with the keeper, 2026-11-20; first run: the cmc feature (metabolon D-005) | proposed | `AGENTS.md`, after the retrospective |
