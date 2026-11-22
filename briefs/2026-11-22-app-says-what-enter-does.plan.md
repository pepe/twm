# Plan: a handle's app says what Enter does

Planner's answer to briefs/2026-11-22-app-says-what-enter-does.md (branch edit/2026-11-22-app-says-what-enter-does, brief 5613f72). No decision ID is assigned yet.

## Context

Since `25d551f` (2026-11-02) a handle's line submits on Enter and Ctrl+Enter and breaks only on Alt+Enter (`twm/handle.janet:332`, `editor/opts`). Windows Terminal takes Alt+Enter for full screen, so cmc's todos can never have more lines. The keeper wants the policy out of twm: the handle gives the mechanism, the app says which lines Enter submits. Done = an app can say "Enter submits a command, breaks a todo", and an app that says nothing behaves as agreed, both shown by tests, with no app's grammar in twm.

## Findings from the sources

- **Who uses a handle session today:** only metabolon's cmc (`:quick`/`:hold` as functions, `:input? false`, `:mouse false`). tots' `wright.janet` and `environment.janet` only list `"twm/handle"` among modules to load; tots' `tdm.janet` uses `=>handle/initial-state`, not a session. So no default can break tots.
- **gp/tui:** `editor/key` checks `:submit` keys before `:newline` keys (`gp/tui.janet:681`). Shift+Enter arrives as `{:key :enter :shift true}`, Ctrl+Shift+Enter as `{:key :ctrl-enter :shift true}`, but only when the terminal sends modifier encodings (CSI u / `modifyOtherKeys`). In legacy input, Enter is `\r` and Ctrl+Enter is `\n` (Ctrl+J too) with no Shift. Windows reads the console as VT bytes (`windows-reader`), so what Windows Terminal sends decides this. Check it by hand (see Verification).
- **The Canon:** "handles" appears only in a list of operative truth (`CANON.md` ~2561), and "console" only as "the MTB console" (~3172). *Line* (the live line), *quick key*, *submit* and *break* are not in the Canon. They are named provisional in the report. The code already uses them, and nothing new claims a Canon concept.
- **For the analyst (not the plan's to settle):** the metabolon rule in "What is decided" says both "Enter submits a line begun by a quick key" and "where the line came from (typed, quick key, the cloud) does not matter". The mechanism below supports either reading. Metabolon's brief should say which one it means.

## Answers to "To find out"

1. **The app's word.** Add an app key `:submits?`, a function `(fn [text quick])` asked when Enter is pressed in the line. `text` is the line. `quick` is the text of the quick key that began it (`"$"`, `"b"`), or nil. It returns true when Enter submits and false when it breaks. It is a function, like `:click`, because cmc decides from the text (`/b3`, bare numbers) and from where the line began. Rejected alternatives:
   - Editor keys given by the app: these are fixed and cannot depend on the line.
   - A table of prefixes: it cannot say "bare numbers while planning" or "begun by `$`".
   - `:quick`/`:hold` already take "table or function asked at every key", but a table makes no sense when the answer depends on the text.
2. **What a line knows of itself.** The handle keeps the quick key as state (`:quick`), as `4fc5992` did. It is set when a quick key begins the line and cleared by `leave-line` (submit, Esc, hold). It is not cleared by `i`, which only enters a line already left, so `quick` is nil then. A cloud pick or click into the line leaves it unchanged. The handle passes `quick` to the app and keeps no grammar of its own.
3. **The default** (an app with no `:submits?`). Recommended: **today's rule, Enter submits every line.** What each option means:
   - *Today's:* cmc and tots unchanged until they opt in, nothing breaks. cmc's todos stay one-line until metabolon's brief, which is already planned.
   - *`4fc5992`'s* (Enter submits only quick lines): cmc changes without opting in. A command typed from `i` (`/b3`) would break on Enter instead of running.
   - *gp/tui's* (Enter breaks, Ctrl+Enter submits): cmc's quick lines (`b 3 ⏎`, planning `p ⏎`) stop working. Its hints `⏎` become false.
   - Only the default is twm's policy now, and an app overrides it with one key. tots is unaffected under every option.
4. **Alt+Enter.** Keep it as a key that always breaks. It costs nothing, works in other terminals, and works in Windows Terminal once full screen is unbound. It is no longer the only way to break, because an app can make Enter break.
5. **Shift.** Shift never changes whether a key submits; it only marks `advance` when a key does submit. Advance is reached with Shift+Enter on a line Enter submits, or Ctrl+Shift+Enter on any line, where the terminal reports Shift. Shift+Enter on a line Enter breaks just breaks it. The doc says the terminal must report Shift. Whether Windows Terminal reports Shift is checked by hand (Verification), and the result goes in the report, not the code.
6. **Canon words.** Provisional: *line*, *quick key*, *submit*, *break* (see Findings). "Handle" is used, not defined, by the Canon.

## The change: `twm/handle.janet` only

- `editor/opts` (l.332): `{:prompt "> " :submit [:ctrl-enter] :newline [:enter :alt-enter]}`, docstring updated. Without the handle stepping in, the editor breaks on Enter and submits on Ctrl+Enter.
- New private `enter-submits?` next to `quick-line`: `(fn [state text])` returns `((get-in state [:app :submits?] (fn [&] true)) text (state :quick))`. Not wrapped in `try`, like `:quick` and `:hold` are not.
- `leave-line` (l.336) also does `(put state :quick nil)`.
- In `^key`, the in-line branch (l.439): the case key becomes `(if (and (= key :enter) (enter-submits? state (tui/editor/text ed))) :submit (tui/editor/key ed k (get state :left cols)))`, the same form `4fc5992` used. The `:submit` arm stays as it is: blank lines are still not submitted, advance is still `(k :shift)`, and the line is still left.
- In the quick-key branch (l.447): also `(put state :quick (k :text))`.
- The `session` docstring: add `:submits?` to the app keys. Rewrite the keys paragraph: Ctrl+Enter submits; Enter submits when `:submits?` says so (every line by default) and otherwise breaks; Alt+Enter breaks; Shift held with a key that submits means advance, where the terminal reports Shift. In the first paragraph, "what Ctrl+Enter would do" stays true.
- Untouched: the cloud (Enter on a picked button still takes it in, since that branch comes first), the hold (it submits on its own), click, Esc, and the aside.

## Tests: `test/handle.janet`

Existing `:handle-quick`, `:handle-cloud` and `:handle-hold` stay as they are. They show the default (an app with no `:submits?`). Add a suite `:handle-enter`, reusing `press`, `line` and `editor` from `:handle-quick`:

- An app whose `:submits?` is `(fn [t q] (or q (string/has-prefix? "/" t)))`:
  - From `i`, `x` then Enter breaks (`"x\n"`, still in the line). Ctrl+Enter then submits it.
  - From `i`, `/b3` then Enter submits.
  - Quick key `$` (a quick line `"$"`) then Enter submits, and the function was given `"$"`. A recording `:submits?` checks the arguments.
- Arguments: after a quick line is left by Esc, then `i`, the function gets `quick` nil, so the quick key is forgotten.
- A cloud pick (Tab, Enter) still submits nothing, and Enter then asks `:submits?` with the picked text.
- A blank line: with `:submits?` true, Enter submits nothing and stays in the line.
- Shift: `{:key :enter :shift true}` on a line Enter submits gives advance true (`(get watched…)`, or check `submitted` through a recording `:submit`; the simplest is to inspect the watch result the same way the existing tests do). On a line Enter breaks it breaks. `{:key :ctrl-enter :shift true}` submits with advance.
- Alt+Enter breaks even when `:submits?` says true.

`test/docs.janet` covers the docstrings.

## Commits on `edit/2026-11-22-app-says-what-enter-does`

One commit with the code and tests: "Let a handle's app say which of its lines Enter submits". Trailers: `Brief: briefs/2026-11-22-app-says-what-enter-does.md`, `Drafted-by: Claude Opus 5.5 (claude-opus-5-5)`, and `Refs: D-0xx` once the keeper assigns it. No `Co-Authored-By` (tots' rules). No push, no tag. Ask once for deletion rights before the first commit (tots' rule on lock files).

## Verification

- `janet-pm test` from the repository root. The whole suite must pass, `test/docs.janet` included. On Windows only; CI covers the others.
- `janet test/handle.janet` for the quick loop.
- By hand, with the keeper in Windows Terminal: a scratch script in the scratchpad using `gp/tui` `open`/`key-producer` that prints the decoded keys for Enter, Shift+Enter, Ctrl+Enter, Ctrl+Shift+Enter and Alt+Enter. The result answers the Shift question in the report. No code depends on it.
- Report: the change, the answers above, the open point for the analyst (metabolon's rule), and any deviation.
