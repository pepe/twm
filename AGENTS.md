# Working rules for AI participants

twm keeps its own ledger, and follows the working rules of tots' `AGENTS.md` at the tag `governance-3`, apart from its sections on the box and on its secrets (D-009):
`git -C ~/code/tots show governance-3:AGENTS.md`, or https://git.sr.ht/~pepe/tots/tree/governance-3/item/AGENTS.md.
tots runs on twm, but rules are text: following them makes no dependency at run time. This file adds to them and never loosens them. If the two seem to conflict, ask the keeper.
Claude Code reads this file through `CLAUDE.md`.

## Before anything

1. `TELOS.md`, then `ledger.md` here, then tots' rules at the same tag.
2. `CANON.md`: "Reading the Canon", and the sections the work touches. `README.md` for the modules.

## The Canon

- `CANON.md` is the Canon, and it is the keeper's text. Do not edit it unless he asks.
- The Canon is published with the library (D-002), under the repository's MIT licence for now (D-008): every release tag carries its state. A change to it goes in a commit of its own, never mixed with code, so a release's diff tells the two apart.
- Use the Canon's words. Code may not claim a concept the Canon lacks; a word it lacks is named as provisional.
- When the code and the Canon disagree, say which looks outdated and ask; do not assume either is right.

## Dependents

- A change made for a dependent refers to the dependent's decision: `Refs: metabolon D-005`.
- `make-send-email` exists in twm and in gp, and interstudy resolves twm's. The two copies are kept identical and changed together.

## Releases

- Releases are tags with the version in `bundle/info.jdn`, and only the keeper makes them. twm is at 0.x: its API may move between minor versions (D-004).
- Never rewrite a commit that a release tag, a dependent or an environment on the box names.
- The suite passes before a merge; both CI runs (builds.sr.ht, GitHub Actions) must stay green.

## Public

- This repository is public, and GitHub is a mirror of sr.ht (D-003). Never commit a secret, a host of the box, or anyone's data.
