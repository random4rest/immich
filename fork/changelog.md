# Changelog (fork)

Personal-fork changes only. Upstream changes are tracked by their own git tags and aren't repeated here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are `vX.Y.Z-personal.N` where `vX.Y.Z` is the upstream tag we're sitting on.

## [Unreleased]

### Changed
- `server/nest-cli.json` → `deleteOutDir: true`. Prevents the stale-`dist/`-migration footgun that contaminated our DB when switching between branches with different schemas (see [agents.md §9.2](./agents.md#92-the-stale-dist-migrations-footgun)).

---

## Upstream syncs

| Date | Sync | Notes |
|---|---|---|
| 2026-05-05 | Forked from `v2.7.5` | Fresh start. New repo. New merge-based policy. See [agents.md](./agents.md). |
