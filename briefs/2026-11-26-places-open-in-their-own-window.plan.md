# Plan: a place entered from another Thicket opens as its own page

Planner's answer to briefs/2026-11-26-places-open-in-their-own-window.md (branch edit/2026-11-26-places-open-in-their-own-window, brief fb89e08). D-012; locker D-003.

## Context

Locker opens each door's place in a window of its own (`/open` posts to the place's `/_door/open`). What drew a place into an Avatar's page serves nothing, yet stays in every place:

- the cross-origin answers;
- the bearer;
- every `:door/address` branch;
- the door helpers;
- the scoped stylesheets.

This removes them from twm first (tots D-051). The admission stays. Done = a place entered from another Thicket is always its own page, with its own cookie, and nothing in twm renders for an Avatar's page or answers across origins; the admission works as before. Tests show both.

## Findings from the sources

- Every commit, name, file and Canon passage the brief cites exists and says what the brief says:
  - the commits `e4b3a70`, `dc34c94`, `24ecf40` and `5ddb952`;
  - `CANON.md` 1863–1869;
  - Locker's `avatar.janet` `/open`.
- **For the analyst:** the brief says "No ledger ID is assigned here", but D-012 was recorded afterwards (`0b7bdc0`). The commits carry `Refs: D-012`.

## Answers to "To find out"

1. **What goes.** The brief's list is right, and nothing on it serves anything else. These also exist only for the embedding:
   - in the sentry: the private `door/content` and the branches of its two callers; the `:door/address` branches in `session/check-with` and `navigations-only`; the exported `bearer`; and the bearer table in `=>session/?live`;
   - in `app.janet`: `cors/conn`, `door/sheets`, and the address prefix and its `named?` test in `ds/action-with`;
   - in the schema: `:door/css` and its `:public` assertion;
   - in the docs: the docstring of `tree/session/cap`, and step 3 of README "Entering from another Thicket".

   These stay:
   - `door/base` (Locker's `/open`, Present Star);
   - `door/held?` (`door/admit`);
   - `door/token-grammar`;
   - `ds/action-with` with its options;
   - the message argument of `handover/transition` (the ordinary path passes it too).
2. **The bearer.** Nobody else presents one. Its only users are the embedding's:
   - Locker's `$_bearer`;
   - Present Star's `psGo` and `psNote`, and its test helper.

   `tree.janet` only describes it. So `session/presented` and `=>session/?live` read the cookie alone, and a logout ends only the sessions its cookies name.
3. **`:origins`.** It keeps its name and means only "Avatars may open this place from here". `:address` stays required with it, for the redirect. Present Star's `sentry.janet` also reads the entrance's first `:origins` as the Locker to send people to. That reading is the dependent's own, and it survives because the name stays.
4. **Where a post to `/_door/open` came from.**
   - Chrome, Edge, Safari and Firefox (since 70) send `Origin` on a cross-origin form post. It is `null` only under `Referrer-Policy: no-referrer` or from an opaque origin.
   - Locker's `/open` sets no such policy, and it is opened with `rel="noopener"`, not `noreferrer`, so its post carries Locker's origin.
   - `Origin` is compared exactly against `:origins`. A post from another origin, from `null` or from none is answered as a malformed one: 303 to the place, no cookie.
5. **A conf still naming `:door/css`.** gp's `validator` (`gp/data/schema.janet`) checks only the keys it lists, so a conf naming it passes and is ignored, and `/_door.css` answers 404. The dependents drop it on their own briefs.
6. **What a window's session lives by.** The library already has `:entry/end avatar token`, which ends one session. Locker can stop ending all of an avatar's sessions when its Avatar stands up again, with nothing new in twm. An expiry of door sessions is needed only if the keeper wants sessions to lapse on their own, and it would be a brief of its own.
7. **The Canon's words.**
   - "Presentation containment" (`CANON.md` 1863–1869) still stands as a warning, but no code embodies its "scoped style, bounded navigation" now.
   - "Door" keeps two senses in the code: the guardian's way in by a Yarlyk (`door/*`, `/_door/open`), and the place's HTTP listener in the sentry's docstrings (`place/secondary?`, `/content`).
   - The sense of `#door` as an element of an Avatar's page leaves with the change.

   The Canon is the keeper's to change.
8. **What each dependent must change to move onto the release:**
   - **Locker:** drop `<door/entered/>`, which is twm's `door/<entering/>`, the `$_bearer` signal, the bearer of `/leave` and entering into its page. Keep `/open`, and decide whether its Avatar standing up again still ends the door's sessions.
   - **Present Star:**
     - drop `<door/stage/>`, `<door/controls/>` and the bearer calls in `psGo` and `psNote`;
     - stop using `door/link`, `door/absolute`, `door/<stylesheet/>` and `door/msg/closed`;
     - drop its `:door/address` branches and `:door/css` from its confs;
     - rewrite the door cases of `test/presenter.janet`.
   - **Metabolon:** drop its `door/bearer-option`, the `door/entering?` and `door/stage` branches (`bill.janet`), `door/link` (`dashboard.janet`), and the same in `environment.janet` and `planner.janet`.
   - **tots:** drop the `/_door.css` location in `edge.janet`, and the `:door` flag that writes it. The `:origins` a crossing writes stay.
   - **Interstudy:** nothing beyond the upgrade.

## The change, file by file

- **`twm/door.janet`:** remove `door/bearer`, `door/leave`, `door/<entering/>`, `door/<closed/>`, `door/msg/entering`, `door/msg/closed`, `door/enter`, `door/entering?`, `door/link`, `door/go`, `door/absolute` and `door/<stylesheet/>`. In the docstring of `door/admit`, the token is posted to `/_door/open`.
- **`twm/app.janet`:**
  - Remove `cors/headers`, `cors/conn`, `cors/wrap`, `door/css-grammar`, `door/scope-css`, `door/sheets`, `door/css` and `door/css-route`.
  - Factor the routes and middleware of `^space/http` out as `space/handler`, without `cors/wrap` or `/_door.css`, so a test can ask a place without a socket.
  - `door/open-route` checks `Origin` against `:origins`.
  - `ds/action-with` renders `@method('parts', {options})` alone.
- **`twm/sentry.janet`:**
  - `session/presented` and `=>session/?live` read the cookie alone.
  - Delete `bearer` and `door/content`.
  - Remove the `:door/address` branches from `session/check-with`, both `/content` handlers and `navigations-only`.
- **`twm/schema.janet`:** remove `:door/css` and its assertion. Keep `:origins` → `:address`.
- **`twm/tree.janet`:** the docstring of `session/cap`.
- **`README.md`:** step 3 of "Entering from another Thicket". The Avatar posts the token to the place's `/_door/open`, which takes posts only from its `:origins`, and the place opens as its own page with its own cookie.

## Tests

- **`test/door.janet`:**
  - `:door-cookie-only`: a live token opens the place as its cookie, and a bearer opens nothing.
  - `:door-own-page`, asked through `space/handler` with an allowed `Origin`:
    - no `Access-Control-*` header, and no 204 to a preflight;
    - actions rendered root-relative;
    - a refused session answered 401 on the place's own page;
    - a logout that ends no session a bearer names;
    - `:door/css` let be, and `/_door.css` answering 404.
  - `:door-open`:
    - an allowed origin gets the cookie;
    - another origin, `null` or none gets no cookie and is still sent to the place;
    - a malformed body and a GET get no cookie either.
  - The suites for admitting, refusing, ending and the RPC stay as they were.
- **`test/identities.janet`:** the bearer assertions become cookie ones, or refusals of a bearer.
- **`test/docs.janet`:** unchanged.

## Verification

1. Run the whole suite in a local `dev/` tree, as README "Development" says: `janet-pm env dev`, `janet-pm deps`, `janet-pm install`, `janet-pm test`. The global Janet library's natives were built for another Janet, so `dev/` is used.
2. Grep `twm/`, `test/` and `README.md` for `cors/`, `:door/address`, `Bearer`, `_bearer`, `door/css` and `#door`: only the tests' refusals remain.
3. Push nothing; CI runs when the keeper pushes.

## Commits

The code and its tests go in one commit, because the removals and the `Origin` check meet in the same functions of `app.janet`. The README goes in a second. Trailers: `Brief:`, `Drafted-by: Claude Opus 5.5`, `Refs: locker D-003`, `Refs: D-012`.
