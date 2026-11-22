# Plan: a handle's app says what Enter does

Planner's answer to briefs/2026-11-22-app-says-what-enter-does.md (branch edit/2026-11-22-app-says-what-enter-does, brief 5613f72). No decision ID is assigned yet.

## Context

Since `25d551f` (2026-11-02) a handle's line submits on Enter and Ctrl+Enter and breaks only on Alt+Enter (`editor/opts` in `twm/handle.janet`). Windows Terminal takes Alt+Enter for full screen, so cmc's todos can never have more lines. The keeper wants the policy out of twm: the handle gives the mechanism, the app says which lines Enter submits. Done = an app can say "Enter submits a command, breaks a todo", and an app that says nothing behaves as agreed, both shown by tests, with no app's grammar in twm.

## Findings from the sources

- **Who uses a handle session today:** only metabolon's cmc (`:quick`/`:hold` as functions, `:input? false`, `:mouse false`). tots' `wright.janet` and `environment.janet` only list `"twm/handle"` among modules to load; tots' `tdm.janet` uses `=>handle/initial-state`, not a session. So no default can break tots.
- **gp/tui:** `editor/key` checks `:submit` keys before `:newline` keys, so the handle steps in on Enter before the editor sees it, as `4fc5992` did.
- **The Canon:** "handles" appears only in a list of operative truth, and "console" only as "the MTB console". *Line* (the live line), *quick key*, *submit* and *break* are not in the Canon, so they are provisional. The code already used them, and nothing new claims a Canon concept.
- **For the analyst:** the metabolon rule in "What is decided" says both "Enter submits a line begun by a quick key" and "where the line came from (typed, quick key, the cloud) does not matter". The mechanism supports either reading. Metabolon's brief should say which one it means.

## Answers to "To find out"

1. **The app's word.** Add an app key `:submits?`, a function `(fn [text quick])` asked when Enter is pressed in the line. `text` is the line. `quick` is the text of the quick key that began it (`"$"`, `"b"`), or nil. It returns true when Enter submits and false when it breaks. It is a function, like `:click`, because cmc decides from the text (`/b3`, bare numbers) and from where the line began. Rejected alternatives:
   - Editor keys given by the app: these are fixed and cannot depend on the line.
   - A table of prefixes: it cannot say "bare numbers while planning" or "begun by `$`".
2. **What a line knows of itself.** The handle keeps the quick key as state (`:quick`), as `4fc5992` did. It is set when a quick key begins the line and cleared by `leave-line` (submit, Esc, hold). So a line entered with `i` has `quick` nil. A cloud pick or click into the line leaves it unchanged. The handle passes `quick` to the app and keeps no grammar of its own.
3. **The default** (an app with no `:submits?`): today's rule, Enter submits every line. What each option means:
   - *Today's:* cmc and tots are unchanged until they opt in, and nothing breaks.
   - *`4fc5992`'s* (Enter submits only quick lines): cmc changes without opting in. A command typed from `i` would break on Enter instead of running.
   - *gp/tui's* (Enter breaks, Ctrl+Enter submits): cmc's quick lines (`b 3 ⏎`, planning `p ⏎`) stop working.
4. **Alt+Enter.** It stays a key that always breaks. It works in other terminals, and it is no longer the only way to break, because an app can make Enter break.
5. **Canon words.** Provisional: *line*, *quick key*, *submit*, *break*.

## The change: `twm/handle.janet`

- `editor/opts`: `{:prompt "> " :submit [:ctrl-enter] :newline [:enter :alt-enter]}`. Without the handle stepping in, the editor breaks on Enter and submits on Ctrl+Enter.
- A new private `enter-submits?` asks the app's `:submits?` with the line and `(state :quick)`, and gives true when the app says nothing.
- `leave-line` clears `:quick`, and a quick key sets it.
- In `^key`, Enter in the line is `:submit` when `enter-submits?` says so; otherwise the editor has it. The `:submit` arm is unchanged: blank lines are not submitted, and the line is left.
- The `session` docstring names `:submits?` and says what Ctrl+Enter, Enter and Alt+Enter do.
- Untouched: the cloud, the hold, click, Esc and the aside.

## Tests: `test/handle.janet`

The existing suites show the default. A new suite, `:handle-enter`, shows:

- With an app whose `:submits?` is `(fn [t q] (or q (string/has-prefix? "/" t)))`:
  - Enter breaks `x`, and Ctrl+Enter then submits it.
  - Enter submits `/`.
  - Enter submits a line begun by the quick key `$`, and `:submits?` is given `"$"`.
- A quick key is forgotten once its line is left.
- Alt+Enter breaks a line Enter would submit.
- A cloud pick submits nothing, and Enter then asks about the picked line, with no quick key.
- A blank line is not submitted, even when the app says Enter submits.

## Verification

`janet-pm test`: the whole suite passes, `test/docs.janet` with it. This was run on Windows only; CI covers the other platforms.
