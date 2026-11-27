# Brief: A logout is asked over Datastar, or it changes nothing

## Telos

twm's `/logout` answers any GET: it ends the sessions the request presents, stands a symbiont down, and streams the way back as Datastar events. A link, an image or a form on any other page can therefore sign a person out of any place built on twm, since the browser sends the place's cookie with a navigation to it; and a person who navigates there lands on an event stream, with nothing taking them back.
Nobody gains a session by it, but a stranger should not be able to end one. Locker closed this for its standing Avatars (locker D-008); once an Avatar has stood down, its sentry answers `/logout` through twm, and the gap is open again there, as it is at every place of Metabolon, Present Star and Interstudy.
Every caller of `/logout` in those thickets already asks over Datastar (`ds/get`, `@get`), which says so in the header `Datastar-Request: true`: a header that no link, image or form can send, and that a script from another origin can send only past a preflight the route never answers.
Judge "done" by that: twm's `/logout`, wherever a guardian or a symbiont routes it, changes anything only when asked over Datastar; any other request is sent to the place's own address and changes nothing: no session ends, and nothing stands down; shown by tests.

## What to read first

1. `AGENTS.md`, `TELOS.md` and `ledger.md` here (D-013, which this brief records), and through them tots' rules at `governance-4`, D-051 above all.
2. `twm/sentry.janet`: `/logout`, `logout/response`, `logout/standdown-after`, `StandDown`, `session/presented`, the guardian's routes (`"/logout"` near the end), and `navigations-only`.
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
- **The header.** How gp hands header names to a handler, and whether the check takes `true` only or the header's presence.
- **The log.** Whether a logout turned away says so, naming no token.
- **The survey.** Confirm that no caller in Metabolon, Present Star, Interstudy, Locker or tots asks `/logout` without Datastar; bring back any that does.

## The steps

1. Plan the change to `twm/sentry.janet`, its docstrings and `README.md` where it speaks of logout, and the tests: a guardian's and a symbiont's `/logout` without the header, with a live session or without, redirect to the place's address, end no session and stand nothing down; with the header they do what they do now. Show the plan to the keeper before writing code.
2. Carry it out on `edit/2026-11-27-logout-only-over-datastar`. The whole suite passes, `test/docs.janet` with it.
3. Report the result and any deviation; the keeper merges, and decides whether and when a release is made.

## Rules

- Plan first and show the plan to the keeper before writing code.
- Change only `twm/`, `test/` and `README.md`. Not `CANON.md`; not gp; not Locker, Metabolon, Present Star, Interstudy or tots.
- No release or tag; no push unless the keeper asks.
- Commits carry `Brief: briefs/2026-11-27-logout-only-over-datastar.md`, `Drafted-by:` with the model and version, and `Refs: D-013`, with `locker D-008` where it is the reason.
