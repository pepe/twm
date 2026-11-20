# Working rules for AI participants

twm is governed on its own (D-001). tots and every thicket on the box depend on twm; twm depends on none of them, so it does not inherit their rules. What it shares with them is restated here.
The keeper (Josef) decides. Assistants plan, write code and run what he asks; he merges and he tags.
Claude Code reads this file through `CLAUDE.md`.

## Before anything

1. `TELOS.md`: why this repository exists.
2. `ledger.md`: accepted decisions bind. If one looks wrong, ask; do not work around it.
3. `CANON.md`: "Reading the Canon", and the sections the work touches. `README.md` for the modules.
4. The brief in `briefs/` that the work answers.

Work begins from a brief. Plan first and show the plan before writing code.
Scripts are written in Janet.

## The Canon

- `CANON.md` is the Canon, and it is the keeper's text. Do not edit it unless he asks.
- The Canon is published with the library (D-002): every release tag carries its state. A change to it goes in a commit of its own, never mixed with code, so a release's diff tells the two apart.
- Use the Canon's words. Code may not claim a concept the Canon lacks; a word it lacks is named as provisional.
- When the code and the Canon disagree, say which looks outdated and ask; do not assume either is right.

## Dependents

- A change made for a dependent refers to the dependent's decision: `Refs: metabolon D-005`.
- `make-send-email` exists in twm and in gp, and interstudy resolves twm's. The two copies are kept identical and changed together.

## Branches, commits and releases

- Work on `edit/<yyyy-mm-dd>-<scope>`. The keeper may create such a branch for an assistant, or work on one himself. Only the keeper commits to `master`, or a tool acting on his explicit instruction under his identity, with `Drafted-by:` naming the tool.
- A new brief is the first commit on its branch.
- The keeper merges with `--no-ff`. Never rebase, squash or force-push a branch once a release tag, a dependent or an environment on the box names one of its commits.
- A commit's subject says, in one sentence, what the change makes so ("Keep a handle following while its symbiont is out of reach").
- Trailers: `Drafted-by:` (model and version), `Reviewed-by:`, `Refs:` (`D-###` here, or `<repository> D-###`), `Brief: briefs/<file>`.
- Releases are tags with the version in `bundle/info.jdn`, and only the keeper makes them. twm is at 0.x: its API may move between minor versions (D-004).
- The suite passes before a merge; both CI runs (builds.sr.ht, GitHub Actions) must stay green.
- If Git leaves `.lock` files behind (a workspace that forbids deleting), stop, say so, and leave Git to the keeper.

## Public

- This repository is public, and GitHub is a mirror of sr.ht (D-003). Never commit a secret, a host of the box, or anyone's data.
- Do not infer the keeper's consent, a decision or a release from your own suggestion. Record proposals as proposals.
