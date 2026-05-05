# Release & build flow

This fork builds its own server image, tagged with a version that encodes both the upstream baseline and a personal counter.

## Version scheme

```text
vX.Y.Z-personal.N
└──┬──┘ └──┬───┘
   │      └─ personal counter, starts at 1, increments per release on the same upstream baseline
   └──────── upstream tag we're sitting on (must match fork/upstream-baseline.txt)
```

Examples:
- `v2.7.5-personal.1` — first personal release on upstream `v2.7.5`.
- `v2.7.5-personal.5` — fifth personal release while still on `v2.7.5`.
- `v2.8.0-personal.1` — first release after syncing upstream `v2.8.0` (the counter resets).

The image tag and the git tag are the same string. We never publish ML images — those track upstream's `ghcr.io/immich-app/immich-machine-learning:vX.Y.Z-cuda` directly via `IMMICH_ML_VERSION` in the deploy `.env`.

## Cutting a release

```bash
cd ~/Projects/immich/immich-src
git checkout main
git pull --ff-only origin main
./scripts/release.sh
```

The script:

1. Verifies you're on `main` with a clean tree.
2. Reads `fork/upstream-baseline.txt` → e.g. `v2.7.5`.
3. Finds the highest existing `v2.7.5-personal.N` git tag → bumps `N` (or starts at 1).
4. Confirms the new version with you (`v2.7.5-personal.6` — proceed? Y/n).
5. Builds `immich-server:v2.7.5-personal.6` with `--build-arg BUILD_ID=v2.7.5-personal.6` (the SvelteKit hash fix from [agents.md §9.3](./agents.md#93-sveltekit-__sveltekit_hash-mismatch--the-spinner-of-death-bug)).
6. Runs the SvelteKit hash sanity check on the built image and aborts on mismatch.
7. Tags the commit `v2.7.5-personal.6` and pushes the tag to `origin`.

The image stays in the local Docker daemon — it's not pushed to a registry by default. Deploy by referencing it from `~/Projects/immich/immich-app/.env` (`IMMICH_VERSION=v2.7.5-personal.6`) and running `./scripts/deploy.sh` over there.

## Manual build (if the script breaks)

```bash
VERSION=v2.7.5-personal.6
docker build \
  -t immich-server:$VERSION \
  --build-arg BUILD_ID=$VERSION \
  -f server/Dockerfile .

git tag $VERSION
git push --follow-tags origin main
```

## Rollback

If a release breaks something, change `IMMICH_VERSION` in `immich-app/.env` back to the prior tag, rebuild prod (`docker compose up -d --force-recreate immich-server` over in `immich-app/`), and you're done.

**DB caveat:** if the bad release ran a migration, rolling back the image won't roll back the schema. Restore from `${UPLOAD_LOCATION}/backups/` instead. See [agents.md §9.5](./agents.md#95-treat-backup-filenames-with-skepticism) for backup verification.

## When to bump the personal counter vs sync upstream

- **You finished a feature or fix on the same upstream baseline** → cut a new personal release (`vX.Y.Z-personal.N+1`).
- **A new upstream tag dropped that you want** → run the [upstream-sync](./upstream-sync.md) ritual first; that produces `vX'.Y'.Z'-personal.1`.

Don't cut a release in the middle of a sync. Finish the sync, then release.
