# Decision ledger

One entry per decision, newest last, except D-001, which says how this ledger is rooted. IDs are stable and never reused.
Status values: `proposed`, `accepted`, `superseded`, `withdrawn`.
A decision of a dependent is named by repository and ID (`metabolon D-005`); it binds there, not here.

D-002 to D-004 were extracted on 2026-11-20 from `README.md` and the history by Claude Opus 5.5, for the keeper to confirm. Each date is that of the commit that brought the decision in.

| ID | Date | Decision | Decided by | Grounds / source | Status | Where |
|---|---|---|---|---|---|---|
| D-001 | 2026-11-20 | twm is governed on its own, not under tots: tots and its tenants depend on twm, and twm on none of them. Its rules restate what it shares with tots' instead of inheriting them | proposed by Claude | the dependency runs one way; inheriting from a dependent would turn it | proposed | `AGENTS.md` |
| D-002 | 2026-08-16 | The Canon lives in this repository, as `CANON.md` | Josef | `2c0f221` "Add current Canon" | accepted | `CANON.md` |
| D-003 | 2026-10-01 | Development happens on sr.ht; GitHub is a mirror with issues and pull requests turned off; patches and reports go by mail | Josef | `README.md` | accepted | `f7e0398` |
| D-004 | 2026-10-01 | twm is at 0.x, and its API may move between minor versions; a dependent pins a release tag | Josef | `README.md` | accepted | `f7e0398` |
| D-005 | 2026-11-20 | A dependent's need enters twm as an option whose default keeps today's behaviour; a default changes only by a decision here | proposed by Claude | first case: metabolon's cmc wants to start outside the line, which `twm/handle` decides for every app (`:input? true`) | proposed | `AGENTS.md` |
