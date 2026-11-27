# Brief: A logout is asked over Datastar, or it changes nothing

## Telos

twm's `/logout` answers any GET: it ends the sessions the request presents, stands a symbiont down, and streams the way back as Datastar events. A symbiont stands down even when the request presents no session at all, so no cookie is needed for that part. A link, an image or a form on any other page can therefore stand a symbiont down at any place built on twm, and where the browser sends the place's cookie with the request (always for a link, which is a navigation; for an image it depends on the browser, since the cookie carries no `SameSite`), it signs the person out too. A person who navigates there lands on an event stream, with nothing taking them back.
Nobody gains a session by it, but another page should not be able to end one. Locker closed this for its standing Avatars (locker D-008); once an Avatar has stood down, its sentry answers `/logout` through twm, and the gap is open again there, as it is at every place of Metabolon, Present Star and Interstudy.
Every caller of `/logout` in those thickets already asks over Datastar (`ds/get`, `@get`), which says so in the header `Datastar-Request: true`: a header that no link, image or form can send, and that a script from another origin can send only past a preflight the route never answers.
The header shuts out other pages, not strangers: anything outside a browser can send it. A stranger still ends no session, having no cookie to present, but can still stand a symbiont down; Locker kept that on purpose (standing down without a session is the way back to the sentry), and this brief leaves it as it is.
Judge "done" by that: twm's `/logout`, wherever a guardian or a symbiont routes it, changes anything only when asked over Datastar; any other request is sent to the place's own address and changes nothing: no session ends, and nothing stands down; shown by tests.

## What to read first

1. `AGENTS.md`, `TELOS.md` and `ledger.md` here (D-013, which this brief records), and through them tots' rules at `governance-4`, D-051 above all.
2. `twm/sentry.janet`: `/logout`, `logout/response`, `logout/standdown-after`, `StandDown`, `session/presented`, the guardian's routes (`"/logout"` near the end), and `navigations-only`. That last one tells Datastar by a `datastar=` query parameter, which a link can carry; the check here is the header, not the query.
3. Locker at `master`: `ledger.md` D-007 and D-008, `briefs/2026-11-27-logout-only-from-the-page.md`, and `avatar.janet` `/sign-out`, where the same check reads `(get-in req [:headers "Datastar-Request"])`; and the commit carrying it out, whose body names this gap.
4. The dependents routing twm's `/logout` themselves, read for what they rely on, not changed: Metabolon `dashboard.janet` (`sentry//logout`, and the `#leave` the other places link to), Present Star `presenter.janet`, Interstudy `admin/init.janet` and `admin/viewer.janet`; and the sentries' `:resume` buttons, which ask `(sentry/place/url "/logout")` over Datastar.

## What is decided

The keeper decided, in conversation with Claude on 2026-11-27 (D-013):

- twm's `/logout` acts only on a request carrying `Datastar-Request: true`. Any other request is answered with a redirect (`303`) to the place's own address, and changes nothing.
- This is the library's default for every guardian and symbiont, not an option a place opts into: no dependent asks `/logout` any other way.
- Locker keeps its own check in `/sign-out`, which decides before it reaches the doors, ahead of twm's `/logout`.
- Nothing in the dependents changes on this brief. Each runs its suite on the result before the box moves to it, which is tots' brief.

## To find out before the plan

These are the analyst's proposals for the planner to check against the code and bring back, not decisions already accepted.

- **Where the check sits.** The proposal: in `/logout` itself, so that every place routing it, guardian or symbiont, gets it, and not only the guardian's route. Say how the place's own address is known there for each (a guardian holding several places, a symbiont), and whether `http/see-other` is the redirect to use.
  Locker's view carries no `:address`, so `place/url "/"` gives `/` there, right only because it stands at the root; check a symbiont standing under a path.
- **The header.** Whether the check takes `true` only or the header's presence. Checked already: gp spells every header name one way whatever case it arrived in (`header-name` in `gp/net/http.janet`), so `"Datastar-Request"` is found as sent by a browser or a proxy; Locker compares `= "true"`.
- **The log.** Whether a logout turned away says so, naming no token, in words alike to Locker's ("turns a sign-out away, not asked over Datastar", with `session=live|none`).
- **The survey.** Confirm that no caller in Metabolon, Present Star, Interstudy, Locker or tots asks `/logout` without Datastar; bring back any that does. Checked once already, at the time of this brief: every caller asks with `ds/get` (Metabolon `dashboard.janet`, Present Star `presenter.janet`, `environment.janet` and `sentry.janet`, Interstudy `environment.janet` and `sentry.janet`), and Locker wraps it in its own check; no plain link was found.
- **A guardian's logout presenting nothing.** `/logout` writes `false` into every view a guardian serves (`^session/cap false`), for every place and every owner, and counts on the tree pushing the capability back once `^session/end-tokens` publishes. Presenting no token, nothing is published, and it looks as if every place the guardian holds then turns everyone away until some other sign-in or logout; with several identities, one person's logout may clear the others' views too. Show by a test whether this is so. It is not D-013's to fix unless the keeper says so; bring it back for a decision of its own.

## The steps

1. Plan the change to `twm/sentry.janet`, its docstrings and `README.md` where it speaks of logout, and the tests: a guardian's and a symbiont's `/logout` without the header, with a live session or without, redirect to the place's address, end no session and stand nothing down; with the header they do what they do now. Show the plan to the keeper before writing code.
2. Carry it out on `edit/2026-11-27-logout-only-over-datastar`. The whole suite passes, `test/docs.janet` with it.
3. Report the result and any deviation; the keeper merges, and decides whether and when a release is made.

## Rules

- Plan first and show the plan to the keeper before writing code.
- Change only `twm/`, `test/` and `README.md`. Not `CANON.md`; not gp; not Locker, Metabolon, Present Star, Interstudy or tots.
- No release or tag; no push unless the keeper asks.
- Commits carry `Brief: briefs/2026-11-27-logout-only-over-datastar.md`, `Drafted-by:` with the model and version (as `Claude Opus 5.5 (claude-opus-5-5)`), and `Refs: D-013`, with `locker D-008` where it is the reason.
