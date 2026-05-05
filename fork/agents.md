# Agent guide

You're working in a personal fork of [`immich-app/immich`](https://github.com/immich-app/immich). Before changing anything, read this file. It is the source of truth for the fork's git policy, branching model, build flow, and known gotchas. The other docs in [`fork/`](.) go deeper on specific topics — start with [readme.md](./readme.md) for the index.

This fork was redesigned from scratch on 2026-05-05 after a previous "detached fork" attempt and an even earlier "track-upstream-main" attempt both produced unrecoverable DB schema drift. The current model — track release tags, merge into a long-running personal branch — is the third iteration. Don't change the model without re-reading [#9 Lessons learned](#9-lessons-learned).

---

## 1. Repository layout

This file lives in the **source repo**. Two sibling repos on the host:

```text
~/Projects/immich/
├── immich-src/   # this repo — code lives here
└── immich-app/   # production deployment — docker-compose.yml + .env + photos folder
```

Never put deployment-specific files (`docker-compose.yml`, `.env`, photos, Postgres data) in `immich-src`. Never put source code in `immich-app`. The deployment repo is a separate local-only git repo today, designed to move to a NAS later.

All fork-specific docs are in [`fork/`](.). Upstream's docs live in [`docs/`](../docs); we keep them as-is so upstream merges don't conflict.

---

## 2. Git remotes & branches

```bash
origin    https://github.com/random4rest/immich.git           # this fork (push here)
upstream  https://github.com/immich-app/immich.git            # FETCH ONLY (push is disabled)
```

`upstream` push URL is set to a sentinel value so any accidental `git push upstream` errors out.

Branches:

| Branch | Purpose |
|---|---|
| `main` | The long-running personal branch and GitHub default. **All custom features land here.** Upstream release tags are merged in via `sync/*` branches (see [upstream-sync.md](./upstream-sync.md)). |
| `sync/vX.Y.Z` | Short-lived branch created during an upstream sync to merge upstream tag `vX.Y.Z` and resolve conflicts in isolation before touching `main`. |
| `feature/*` | Short-lived branches for non-trivial work. Trivial changes can go directly on `main`. |

**Hard rules:**

- **Never force-push `main`.** It would invalidate every personal release tag's history.
- **Never push to `upstream`.** The push URL is a sentinel; if you somehow get past it, stop.
- **Never merge upstream `main`.** Only release tags. See [#9.1](#91-why-we-dont-track-upstream-main).
- **Never rebase upstream commits onto our history.** We merge them in. Conflict resolutions become real commits.

Commit messages: conventional-commit style. Every commit in this repo is "fork code" by definition; no special prefix needed.

```text
feat(web): rotate action on photo viewer
fix(server): handle missing EXIF on rotate
chore(deps): bump sharp to 0.34.0
docs(fork): clarify upstream-sync ritual
```

---

## 3. Implementing a new feature

### 3.1 Branch off `main`

```bash
cd ~/Projects/immich/immich-src
git checkout main
git pull --ff-only origin main
git checkout -b feature/<short-name>
```

Trivial changes (typo fix, log message) can commit directly to `main`. Use judgement.

### 3.2 Run the dev stack with hot-reload

The dev compose lives in [`docker/docker-compose.dev.yml`](../docker/docker-compose.dev.yml). It bind-mounts the entire source tree into the container, so edits in `web/src/`, `server/src/`, and `machine-learning/immich_ml/` are reloaded live.

```bash
cd ~/Projects/immich/immich-src/docker
cp example.env .env             # first time only
docker compose -f docker-compose.dev.yml up -d
```

**Dev runs side-by-side with prod.** Dev uses shifted host ports so the two stacks don't conflict:

| | Dev | Prod |
|---|---|---|
| Web (browser) | `localhost:3001` | `localhost:2283` |
| Server API | `localhost:3283` | `localhost:2283` |
| Postgres | `localhost:5433` | `localhost:5432` |
| ML | `localhost:3103` | `localhost:3003` |
| Node debug | `localhost:9330` / `9331` | n/a |

The **prod stack is what your other devices hit via Tailscale** — keep it on `2283` and `restart: always`.

### 3.3 Where to make changes

| Want to change… | Edit |
|---|---|
| HTTP route, business logic, schema | `server/src/{controllers,services,repositories,schema}/` |
| Web UI | `web/src/{routes,lib}/` |
| Mobile UI | `mobile/lib/` |
| ML model / pipeline | `machine-learning/immich_ml/models/` |
| API contract (DTO) | `server/src/dtos/*.dto.ts` (Zod schemas → also generates the OpenAPI spec) |

After changing a DTO, regenerate the OpenAPI clients used by `web/`, `cli/`, and `mobile/`:

```bash
make open-api    # or: cd open-api && bash bin/generate-open-api.sh
```

See [architecture.md](./architecture.md) for the controller → service → repository flow.

### 3.4 Commit and merge

```bash
git add <files>
git commit -m "feat(<area>): <what>"

git checkout main
git merge --no-ff feature/<short-name>
git branch -d feature/<short-name>
git push origin main
```

Add an entry to [changelog.md](./changelog.md) under `[Unreleased]`. When you're ready to ship, see [release.md](./release.md).

---

## 4. Syncing upstream releases

Every ~2 months (or when a release lands that you want), run the sync ritual. Full procedure in [upstream-sync.md](./upstream-sync.md). Short version:

```bash
git fetch upstream --tags
./scripts/sync-upstream.sh v2.X.Y
# resolve conflicts as the script pauses
# pre-flight migration check runs against a copy of prod's DB
git checkout main && git merge --no-ff sync/v2.X.Y
./scripts/release.sh                   # tags v2.X.Y-personal.1, builds image
```

`fork/upstream-baseline.txt` is the single source of truth for "what upstream tag are we sitting on". The release script reads it; the sync script updates it.

---

## 5. Release & deploy

Personal builds are tagged `vX.Y.Z-personal.N` where `vX.Y.Z` matches `fork/upstream-baseline.txt`. The release script bumps `N` automatically. Full details in [release.md](./release.md). For deployment to the prod stack, see [deployment.md](./deployment.md) and the sibling `immich-app/` repo.

---

## 6. Operational reminders

- **Backups**: Immich's built-in DB backup writes to `${UPLOAD_LOCATION}/backups/`. Take an off-site copy of `library/` + `backups/` (`restic`, `rclone`, etc.).
- **Remote access**: Tailscale on the server + every client. Mobile app and remote browsers point at the Tailscale name.
- **Postgres data**: Lives in the `immich_immich_pgdata` named Docker volume. Never bind-mount Postgres data on WSL2 — race condition can wipe the data dir on Docker restart.
- **`UPLOAD_LOCATION`**: Native WSL ext4 (`/home/law/immich-library`), not `/mnt/c/...`. The 9P protocol overhead on `/mnt/c` significantly slows Postgres and image processing.

---

## 7. Quick reference

| Task | Command |
|---|---|
| Start dev stack | `cd immich-src/docker && docker compose -f docker-compose.dev.yml up -d` |
| Start prod stack | `cd immich-app && docker compose up -d` |
| Stop prod stack | `cd immich-app && docker compose down` |
| Sync from upstream tag | `cd immich-src && ./scripts/sync-upstream.sh vX.Y.Z` |
| Tag and build personal release | `cd immich-src && ./scripts/release.sh` |
| Deploy a built tag to prod | edit `IMMICH_VERSION` in `immich-app/.env`, then `cd immich-app && ./scripts/deploy.sh` |
| Read the codebase | [architecture.md](./architecture.md) |

---

## 8. Push & SSH gotchas

- `origin` uses HTTPS via gh CLI's stored token. If `git push` prompts for credentials, run `gh auth setup-git` once.
- If you switch to SSH (`git remote set-url origin git@github.com:random4rest/immich.git`), make sure your agent has the key loaded (`eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519`).

---

## 9. Lessons learned

### 9.1 Why we don't track upstream `main`

We initially tried to track `upstream/main` so we could pull in features as they landed. That immediately bit us:

- `upstream/main` rolls every PR the moment it lands, including `chore!` and `refactor!` commits with breaking changes that haven't gone through any release validation. Building from `main` produced server images that crashed the web client on load with `TypeError: Cannot read properties of undefined (reading 'env')` (just a spinner forever, see §9.3).
- It applied DB migrations that don't exist in any tagged release, making rollback to `ghcr.io/immich-app/immich-server:vX.Y.Z` impossible without restoring the DB from backup (`corrupted migrations: previously executed migration <ts>-... is missing`).

We then tried "rebase onto release tags" — same problem. Even release tags carry breaking changes (`chore!`, `refactor!`) that conflict with our customizations every cycle, and conflict resolutions during a rebase require understanding upstream's intent for every breaking commit.

The current model — **merge release tags into a long-running personal branch** — gives us:

- Conflict resolutions become real commits in history (auditable, bisectable).
- Personal branch keeps moving forward; upstream merges become "events" in the log.
- No force-pushes. Tags stay valid forever.
- Each release tag has matching `ghcr.io/immich-app/immich-server:vX.Y.Z` available, so we can sanity-check or fall back to upstream's official image.

### 9.2 The stale `dist/` migrations footgun

**Symptom:** Dev stack reapplies upstream-main DB migrations even after switching back to a fork branch that doesn't contain them. `column album.ownerId does not exist` and similar errors.

**Root cause:** `server/nest-cli.json` has `"deleteOutDir": false`. When you build/run upstream main once, the compiled migrations land in `server/dist/schema/migrations/*.js`. Switching git branches doesn't touch `dist/` (it's gitignored). The dev container's `nest start --watch` recompiles changed source files but doesn't remove orphan compiled migrations. Those orphan `.js` files are still in the migrations directory, so the migration runner picks them up at boot and tries to apply them.

**Fix:** Whenever you switch branches between substantially different schemas, run:

```bash
rm -rf ~/Projects/immich/immich-src/server/dist
```

Better: keep `"deleteOutDir": true` in `server/nest-cli.json` (a one-line fork patch worth keeping).

### 9.3 SvelteKit `__sveltekit_<HASH>` mismatch — the spinner-of-death bug

**Symptom:** Web UI loads to the spinning logo and stays there. DevTools console shows `Uncaught (in promise) TypeError: Cannot read properties of undefined (reading 'env')` from a minified chunk. Pretty-printing reveals `var d = globalThis.__sveltekit_<HASH1>.env` where `globalThis.__sveltekit_<HASH1>` is `undefined` because `index.html` initialised a *different* `globalThis.__sveltekit_<HASH2>`.

**Root cause:** `web/svelte.config.js` sets `kit.version.name = process.env.IMMICH_BUILD || Date.now().toString()`. SvelteKit hashes `version.name` into the global namespace. SvelteKit loads the config more than once during a build (SSR/prerender pass + client pass), so `Date.now()` produces two different values on the two passes, hence two different `__sveltekit_<HASH>` globals.

**Fix:** Always pass a stable `BUILD_ID` to the server image build:

```bash
docker build -t immich-server:vX.Y.Z-personal.N \
  --build-arg BUILD_ID=vX.Y.Z-personal.N \
  -f server/Dockerfile .
```

`scripts/release.sh` and `immich-app/docker-compose.yml` both do this automatically. Only standalone `docker build` invocations need it explicit.

**Sanity check after every rebuild:**

```bash
docker exec immich_server sh -c '
  echo "[index.html]"; grep -o "__sveltekit_[a-z0-9]*" /build/www/index.html | sort -u
  echo "[js chunks]";  grep -rho "globalThis.__sveltekit_[a-z0-9]*" /build/www/_app | sort -u
'
```

Both lists must print the same single hash.

### 9.4 Always `--no-cache` after a config change

Layer caching can pin a stale `web/build` directory even after you change source files or build args. After any change to `svelte.config.js`, `vite.config.ts`, the Dockerfile, or build args, do `docker compose build --no-cache immich-server` once. Routine code changes don't need it.

### 9.5 Treat backup filenames with skepticism

A backup file named `immich-db-backup-…-v2.7.5-pg14.19.sql.gz` only tells you what `IMMICH_VERSION` env var the running container had **at backup time**. The schema inside might be from any actually-applied migration set. After every restore, verify:

```bash
gunzip -c <backup>.sql.gz | grep -A 4 'CREATE TABLE public.album '
```

The dump should match the schema your code expects (e.g. v2.7.5 has `album.ownerId`).
