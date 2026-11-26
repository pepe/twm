# Brief: A place entered from another Thicket opens as its own page

## Telos

Since `e4b3a70` and `dc34c94` (2026-11-01 and -04), a place entered through a door can be drawn into the Avatar's page: the browser fetches it across origins with the door's session as a bearer, and the place renders itself for a page that is not its own.
After prolonged use the keeper decided against it (locker D-003): Locker lists a person's doors, and each opens its place in a window of its own, as `/_door/open` (`5ddb952`) already does.
What served the embedding then serves nothing, yet stays in every place: `cors/wrap` in front of its HTTP, a `:door/address` branch in every action `ds/get` and `ds/post` render, in the sentry's `/content` and its session check, in a stray stream's fallback, and a set of helpers its thickets call so that their links and actions also work inside an Avatar's page.
The Canon already warns against what the embedding was: "No foreign king should silently acquire the host's page merely because a door was opened."
Judge "done" by that: a place entered from another Thicket is always its own page, with its own cookie, and nothing in twm renders for an Avatar's page or answers a request across origins; the admission itself (Yarlyk, Baskak, a guardian's door, `:entry/admit`, `:entry/end`, `/_door/open`) stands and works as before, all shown by tests.

## What to read first

1. `AGENTS.md`, `TELOS.md` and `ledger.md` here, and through them tots' rules at `governance-4`, D-051 above all. `CANON.md`: "Reading the Canon", "Security as Field Protection" (presentation containment, near the end), "Baskak and Yarlyk".
2. Locker at its `master`: `ledger.md` D-003; `README.md`; `avatar.janet` `/open`, the one way into a place that stays.
3. The history: `e4b3a70` (admission and `cors/wrap`), `dc34c94` (the Avatar's page kept its own: `door/link`, `door/<entering/>`, the sheets scoped to `#door`), `24ecf40` (`door/absolute`), `5ddb952` (`/_door/open`).
4. `twm/door.janet` whole; `twm/app.janet`: `cors/*`, `door/css-grammar`, `door/scope-css`, `door/css`, `door/css-route`, `door/open-route`, `^space/http`, `ds/action-with`, `ds/action`; `twm/sentry.janet`: `session/presented`, `bearer`, `=>session/?eq` and the check after it, `session/check-with`, `door/content` and its two callers, `navigations-only`, and every other reader of `:door/address`; `twm/schema.janet`, the membrane node; `twm/tree.janet` on bearers; `README.md`, "Entering from another Thicket". Tests: `test/door.janet`, `test/identities.janet`, `test/docs.janet`.
5. The dependents, read for what they use, not changed here: Present Star (`presenter.janet`, `sentry.janet`, its confs and `test/presenter.janet`), Metabolon (`environment.janet`, `dashboard.janet`, `bill.janet`, `planner.janet`, test confs), Locker (`avatar.janet`, `test/crossing.janet`), tots (`edge.janet` and its `/_door.css` location, `expand.janet` where a crossing writes `:origins` and the `:door` flag). Interstudy uses none of the helpers by name, only twm's defaults.

## What is decided

The keeper decided, in conversation with Claude on 2026-11-26 (locker D-003):

- Locker stops embedding; a door opens its place in a window of its own.
- What served only the embedding leaves twm. This brief is the library's part and goes first (tots D-051). Locker, Present Star, Metabolon and tots each follow on a brief of their own, written once this is merged, against what was merged. Each dependent pins a twm release (D-004), so none breaks before it moves.
- The admission stays as it is: `twm/yarlyk`, `twm/baskak`, the door's RPC (`:entry/admit`, `:entry/end`, `:ping`), the session it publishes for its holder, and `/_door/open` turning that session into the place's own cookie.

No ledger ID is assigned here; the keeper assigns one in review of this brief.

## To find out before the plan

These are the analyst's proposals for the planner to check against the code and bring back, not decisions already accepted.

- **What goes.** The proposal: `cors/headers`, `cors/conn`, `cors/wrap` and its use in `^space/http`; the `:door/address` dynamic and every branch reading it; in `twm/door.janet` `door/bearer`, `door/leave`, `door/<entering/>`, `door/<closed/>`, `door/msg/entering`, `door/msg/closed`, `door/enter`, `door/entering?`, `door/link`, `door/go`, `door/absolute`, `door/<stylesheet/>`; `door/css-grammar`, `door/scope-css`, `door/css`, `door/css-route` and `:door/css`. What stays in `twm/door.janet`: the admission, `door/held?`, and `door/base`, which Locker's `/open` uses. Bring back anything else that exists only for the embedding, and anything on this list that serves something else.
- **The bearer.** A session is accepted as `Authorization: Bearer` only for the embedding. The proposal: a place admits its session by its cookie alone, and `session/presented`, `bearer` and the check stop reading the header. Say who else presents a bearer, if anyone (`twm/tree.janet` mentions it).
- **`:origins`.** It now means two things: who may fetch across origins, and that `/_door/open` exists. The proposal: keep the name, so tots' expansion writes it unchanged, and let it mean only the origins an Avatar may open the place from; `:address` stays required with it, for the redirect.
- **`/_door/open` asks where the post came from.** Today it checks nothing, so any site holding a live door session can post it and sign a browser in as that session's holder. The proposal: refuse a post whose `Origin` is not among `:origins`, an absent one included. Say whether any browser Locker supports omits `Origin` on a cross-origin form post.
- **A conf that still names `:door/css`.** Whether the membrane schema refuses a key it does not know. A dependent's conf keeps `:door/css` until its own brief removes it; propose whether twm refuses it, ignores it, or warns.
- **What a window's session lives by.** Today Locker ends a door's sessions when its Avatar stands up again, which also ends the windows still in use. That is Locker's to settle on its own brief; say only whether the library would need a mechanism for it (an expiry of a door's sessions, say). If it would, it is a brief of its own, not this one.
- **The Canon's words.** "Door" names a guardian's way in by a Yarlyk and also a place's HTTP listener, and "Presentation containment" in the Canon describes the embedding. Note where the code's words and the Canon's part after this change; the Canon is the keeper's to change.
- **The release.** What a dependent must change to move onto it, one line per dependent, for the keeper to decide the version.

## The steps

1. Plan from the sources above: the answers to the questions, the removals and the changes file by file, the docstrings and `README.md` that change with them, and the tests that show each case (a place answers no request across origins; actions render root-relative whatever the request; `/_door/open` sets the cookie for an allowed origin and refuses another and none; a door still admits, refuses and ends sessions as before; a bearer opens nothing, if that is accepted). Show the plan to the keeper before writing code.
2. Carry it out on `edit/2026-11-26-places-open-in-their-own-window`. The whole suite passes, `test/docs.janet` with it.
3. Report the result, any deviation, and the list of what each dependent must change. The analyst checks it against the Telos; the keeper merges, and decides whether and when a release is made.
4. Then the analyst writes the dependents' briefs, Locker's first.

## Rules

- Plan first and show the plan to the keeper before writing code.
- Change only `twm/`, `test/` and `README.md`. Not `CANON.md`; not gp; not Locker, Present Star, Metabolon, Interstudy or tots.
- No release or tag; no push unless the keeper asks.
- Commits carry `Brief: briefs/2026-11-26-places-open-in-their-own-window.md`, `Drafted-by:` with the model and version, `Refs: locker D-003`, and this repository's ID once the keeper assigns it.
