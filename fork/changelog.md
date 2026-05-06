# Changelog (fork)

Personal-fork changes only. Upstream changes are tracked by their own git tags and aren't repeated here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are `vX.Y.Z-personal.N` where `vX.Y.Z` is the upstream tag we're sitting on.

## [Unreleased]

### Changed
- Bulk metadata-edit actions (change-date, change-location, change-description, tag) no longer clear the multi-select after success. The selection bar stays open so you can chain edits (e.g. fix the location of a roll, then fix the date without re-selecting). Destructive / view-changing actions (delete, archive, remove-from-album, etc.) still clear because the assets are no longer relevant. Clear manually with Esc or the X on the bar. Touched files are tagged with `// [fork]` for merge visibility.

---

## [v2.7.5-personal.2] — 2026-05-05

Both features were proposed/merged via PRs on `origin/main`.

### Added
- `feat/rotate-action`: rotate action in the timeline selection bar.
- `feat/nominatim-poi-search`: OpenStreetMap POI search in the location picker modal.

### Fixed
- Shellcheck cleanups in `scripts/release.sh` and `scripts/sync-upstream.sh`.

### Build / CI (fork-only)
- Fork-only smoke build workflow (`fork-build.yml`).
- Gated upstream-only CI jobs behind `repository == immich-app/immich` so they don't try to run on the fork.
- `server-medium-tests` clones `test-assets` on forks (where it isn't a submodule).
- `gitignore` for local tool state.

---

## [v2.7.5-personal.1] — 2026-05-05

First personal release on top of upstream `v2.7.5`.

### Changed
- `server/nest-cli.json` → `deleteOutDir: true`. Prevents the stale-`dist/`-migration footgun that contaminated our DB when switching between branches with different schemas (see [agents.md §9.2](./agents.md#92-the-stale-dist-migrations-footgun)).

---

## Upstream syncs

| Date | Sync | Notes |
|---|---|---|
| 2026-05-05 | Forked from `v2.7.5` | Fresh start. New repo. New merge-based policy. See [agents.md](./agents.md). |
