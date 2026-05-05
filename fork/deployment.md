# Deployment

Production deployment lives in the **sibling repo** `~/Projects/immich/immich-app/`. It's a separate local git repo (no remote yet) so it can be moved to a NAS later without dragging the source tree along.

## Why two repos

| Concern | `immich-src/` | `immich-app/` |
|---|---|---|
| Source code | yes | no |
| Compose files for prod | no | yes |
| `.env` with secrets | no | yes (gitignored) |
| Photo library | no | yes (mounted; not in git) |
| Subject to upstream merges | yes | no |
| Where AI agents make edits by default | yes | only when explicitly asked |

Keeping them apart means upstream merges never touch your deployment config, and a NAS migration is just `git clone` + `cp .env`.

## Repo layout

```text
immich-app/
├── docker-compose.yml          # prod compose
├── hwaccel.transcoding.yml     # NVENC for transcoding (RTX 4070)
├── hwaccel.ml.yml              # CUDA for ML
├── .env.example                # commit this
├── .env                        # gitignored — secrets
├── readme.md                   # deploy instructions + NAS migration notes
└── scripts/
    └── deploy.sh               # bumps IMMICH_VERSION + recreates server
```

## Prod stack

| Service | Image | Auto-restart |
|---|---|---|
| `immich-server` | `immich-server:${IMMICH_VERSION}` (built locally from `../immich-src`) | yes |
| `immich-machine-learning` | `ghcr.io/immich-app/immich-machine-learning:${IMMICH_ML_VERSION}-cuda` | yes |
| `redis` (Valkey) | `valkey/valkey:9` | yes |
| `database` | `ghcr.io/immich-app/postgres:14-vectorchord…` | yes |

All four containers have `restart: always`. Combined with Docker Desktop's "Start Docker Desktop when you log in" setting, the prod stack comes back up automatically when Windows boots — no Task Scheduler, no systemd-in-WSL.

## Auto-start on Windows boot

1. Open **Docker Desktop → Settings → General**.
2. Enable **"Start Docker Desktop when you log in"**.
3. Apply.
4. Reboot Windows once to verify. After login, `docker ps` should show the prod stack running.

If you're logged in over Tailscale and don't need the GUI, you can verify remotely too.

## Cutting over to a new release

Done from `immich-app/`, not `immich-src/`:

```bash
cd ~/Projects/immich/immich-app

# Edit .env, set IMMICH_VERSION=v2.7.5-personal.6
${EDITOR:-vi} .env

./scripts/deploy.sh
```

`deploy.sh`:
1. Reads new `IMMICH_VERSION` from `.env`.
2. Builds the server image (or skips if already built — `release.sh` builds it).
3. Recreates only the `immich-server` container (DB, Redis, ML keep running).
4. Prunes dangling images.
5. Runs the SvelteKit hash sanity check.

## Rollback

Change `IMMICH_VERSION` back to the previous tag, re-run `./scripts/deploy.sh`. **Watch for migrations** — if the bad version added one, you need to restore from `${UPLOAD_LOCATION}/backups/` after rolling back the image. See [agents.md §9.5](./agents.md#95-treat-backup-filenames-with-skepticism) for backup verification.

## Backups

Immich's built-in DB backup writes to `${UPLOAD_LOCATION}/backups/` on a schedule configurable in admin settings. Make sure:

1. The backup task is enabled.
2. `${UPLOAD_LOCATION}` is on a disk you back up off-site (`restic`, `rclone`, etc.).
3. After every successful deploy, take an extra one-off backup before doing anything risky (sync, schema migration).

## Moving to a NAS later

When you're ready to move prod off the laptop:

1. Stop prod: `docker compose down` (data is in volumes; no loss).
2. `rsync` the photo library (`${UPLOAD_LOCATION}`) to NAS.
3. Export the DB volume: `docker run --rm -v immich_immich_pgdata:/data -v $(pwd):/host alpine tar czf /host/pgdata.tar.gz -C /data .`
4. Take the latest `${UPLOAD_LOCATION}/backups/` `.sql.gz` as a fallback.
5. On the NAS: install Docker, clone `immich-app`, copy `.env` (or recreate from `.env.example`), restore the volume, `docker compose up -d`.
6. Build the server image on the NAS too (or push to GHCR from your laptop and pull on NAS).
7. Update Tailscale ACLs / DNS so the Tailscale name resolves to the NAS instead of the laptop.

The fork's source tree (`immich-src/`) doesn't need to come along to the NAS unless you want to do builds there.
