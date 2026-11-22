# Brief: A handle's app says what Enter does

## Telos

A handle's line decides by itself what Enter does: since `25d551f` (2026-11-02) Enter submits every line, and Alt+Enter breaks it. That is a choice about one app's input, made in the library for every app. It has already cost metabolon's cmc its todos of more lines: Windows Terminal takes Alt+Enter for full screen, so a line there can never be broken.
The keeper wants this policy out of twm: the handle gives the mechanism, and the app says which of its lines Enter submits.
Judge "done" by that: an app can tell the handle that Enter submits a command and breaks a todo, and a handle whose app says nothing behaves as the plan agrees, both shown by tests, with nothing of any one app's grammar written in twm.

## What to read first

1. `AGENTS.md`, `TELOS.md` and `ledger.md` here, and through them tots' rules at `governance-2`; `CANON.md`, "Reading the Canon".
2. `4fc5992` (2026-10-30), "Let a quick key begin a handle's line, and Enter alone submit it": a line begun by a quick key submitted on Enter, any other broke on Enter and was submitted with Ctrl+Enter.
3. `25d551f` (2026-11-02), "Draw a handle's aside beside its console, and let Enter run the line": `editor/opts` became `:submit [:enter :ctrl-enter] :newline [:alt-enter]`, and the quick line's own rule went. Its other changes (the aside, a blank line not submitted, the line left after a submit, Tab and the cloud) are not in question.
4. `twm/handle.janet`: `editor/opts`, `leave-line`, `asked`, `quick-line`, `^key` (the line's `case`, the quick key's branch, the hold), `session` and its docstring. `test/handle.janet`: the `:handle-quick` and `:handle-cloud` suites; `test/docs.janet`.
5. gp's `gp/tui.janet`: `make-editor` (by default Ctrl+Enter and Alt+Enter submit, Enter breaks), `editor/key`, and how Ctrl+Enter is told from Enter (`with-mods`; Ctrl+J arrives as `:ctrl-enter` too).
6. The handles that use this today: metabolon's `cmc.janet` (`app`, `quick/console`, `quick/planning`, `hold/*`) and tots' `wright.janet` and `environment.janet`. They are read for what they need, not changed.

## What is decided

The keeper decided, in conversation with Claude on 2026-11-22:

- Whether Enter submits a line or breaks it is the app's to say, not twm's. twm's handle offers the way to say it.
- The work is split: twm first, on its own brief and branch; metabolon's use of it comes after, on a brief of its own there.
- For metabolon, later: Enter submits a line begun by a quick key or one that begins with a command; every other line breaks on Enter and is submitted with Ctrl+Enter; where the line came from (typed, quick key, the cloud) does not matter. This is recorded here only so that the plan makes it possible; it is not built here.

No ledger ID is assigned yet; the keeper assigns one in review of this brief.

## To find out before the plan

These are the analyst's proposals and open points for the planner to bring back, not decisions already accepted.

- **The shape of the app's word.** A proposal: an app key, provisionally `:submits?`, a `(fn [text])` telling whether Enter submits the line `text`. Weigh it against alternatives (the editor's keys given by the app, a table of prefixes), and against `:quick` and `:hold`, which may be a table or a function asked at every key.
- **What a line knows of itself.** Whether the app needs more than the text: metabolon's case needs "begun by a quick key", because its quick keys `$` and `!` begin todos, not commands, and its planning lines are bare numbers. Propose whether the handle passes that, keeps it as state (as `4fc5992` did with `:quick`), or leaves it to the app.
- **The default.** What a handle whose app says nothing does: `4fc5992`'s rule (Enter submits a quick line, breaks any other), gp/tui's own (Enter breaks, Ctrl+Enter submits), or today's (Enter submits). Bring back what each means for cmc and for tots until they say anything, and whether any of them breaks.
- **Alt+Enter.** Whether it should stay a way to break a line, though Windows Terminal never lets it through.
- **Shift.** Shift with the submitting key means advance. Say how it is reached once Enter breaks most lines in some apps (Ctrl+Shift+Enter, and whether Windows Terminal lets it through).
- **The Canon's words.** Whether the handle, the line, a quick key and submitting have names in the Canon; name any word it lacks as provisional.

## The steps

1. Plan from the sources above: the change to `twm/handle.janet`, the answers to the questions above, and the tests that show each case (an app that says Enter submits, one that says it breaks, an app that says nothing, a quick line, a line from the cloud, a blank line, Esc, Shift). Show the plan to the keeper before writing code.
2. Carry it out on `edit/2026-11-22-app-says-what-enter-does`: `twm/handle.janet`, its docstring, `test/handle.janet`. The whole suite passes, `test/docs.janet` with it.
3. Report the result and any deviation. The analyst checks it against the Telos; the keeper merges, and decides whether and when a release is made.
4. Then the analyst writes metabolon's brief for cmc's use of it.

## Rules

- Plan first and show the plan to the keeper before writing code.
- Change only `twm/handle.janet` and `test/handle.janet`. Not gp, not metabolon, not tots; not `CANON.md`.
- No release or tag; no push unless the keeper asks.
- Commits carry `Brief: briefs/2026-11-22-app-says-what-enter-does.md`, `Drafted-by:` with the model and version, and `Refs:` once the keeper assigns the decision's ID.
