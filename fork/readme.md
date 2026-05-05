# Fork docs

All personal-fork documentation lives in this folder. Upstream Immich docs are untouched and live at [`docs/`](../docs).

| File | Read it when... |
|---|---|
| [agents.md](./agents.md) | You're an AI agent, or you're a human onboarding to this fork. Start here. |
| [architecture.md](./architecture.md) | You want a fork-specific tour of the codebase. Pairs with upstream's [architecture doc](../docs/docs/developer/architecture.mdx). |
| [upstream-sync.md](./upstream-sync.md) | You're about to merge a new upstream release tag (the ~2-month ritual). |
| [release.md](./release.md) | You're tagging and building a personal version. |
| [deployment.md](./deployment.md) | You're operating the prod stack, or moving it to a NAS. |
| [changelog.md](./changelog.md) | You want to know what changed in this fork, and when. |
| [upstream-baseline.txt](./upstream-baseline.txt) | One line — the current upstream tag this fork is based on. Source of truth for the release script. |

## TL;DR

- This fork tracks upstream **release tags only** (never `main`).
- We **merge** new upstream tags into a long-running `main` branch (never rebase, never force-push).
- Personal builds are tagged `vX.Y.Z-personal.N` where `vX.Y.Z` is the upstream tag we're sitting on.
- Source code lives here (`immich-src/`); deployment files live in the sibling `immich-app/` repo.
