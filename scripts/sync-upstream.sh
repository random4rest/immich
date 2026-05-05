#!/usr/bin/env bash
#
# sync-upstream.sh — merge a new upstream release tag into this fork.
#
# Implements the procedure documented in fork/upstream-sync.md.
#
# Usage:
#   ./scripts/sync-upstream.sh vX.Y.Z                         start a sync
#   ./scripts/sync-upstream.sh --check-migrations vX.Y.Z      dry-run migrations against a copy of prod DB
#   ./scripts/sync-upstream.sh --finish vX.Y.Z                merge sync/vX.Y.Z back into main
#   ./scripts/sync-upstream.sh --abort vX.Y.Z                 throw away sync/vX.Y.Z
#
# Environment:
#   PROD_BACKUP   path to a .sql or .sql.gz to use for the migration check
#                 (default: newest file in $UPLOAD_LOCATION/backups/)
#   UPLOAD_LOCATION  defaults to /home/law/immich-library

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

UPLOAD_LOCATION="${UPLOAD_LOCATION:-/home/law/immich-library}"
PG_IMAGE="ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"

mode="start"
TAG=""
for arg in "$@"; do
  case "$arg" in
    --check-migrations) mode="check" ;;
    --finish) mode="finish" ;;
    --abort) mode="abort" ;;
    --help|-h) sed -n '2,17p' "$0"; exit 0 ;;
    v[0-9]*.[0-9]*.[0-9]*) TAG="$arg" ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "ERROR: pass an upstream tag like v2.8.0" >&2
  exit 2
fi
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: '$TAG' is not a valid release tag (must be vX.Y.Z)" >&2
  exit 2
fi

SYNC_BRANCH="sync/$TAG"

ensure_clean() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is dirty. Commit or stash first." >&2
    git status --short >&2
    exit 1
  fi
}

cmd_start() {
  ensure_clean
  echo "==> Fetching upstream tag $TAG"
  git fetch upstream tag "$TAG" --no-tags
  if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "ERROR: upstream tag $TAG not found" >&2
    exit 1
  fi
  echo "==> Switching to main and bringing it up to date"
  git checkout main
  git pull --ff-only origin main
  if git rev-parse "$SYNC_BRANCH" >/dev/null 2>&1; then
    echo "ERROR: $SYNC_BRANCH already exists. Use --abort to discard or --finish to complete." >&2
    exit 1
  fi
  echo "==> Creating $SYNC_BRANCH"
  git checkout -b "$SYNC_BRANCH"
  echo "==> Merging upstream $TAG"
  if ! git merge --no-ff "$TAG" -m "merge upstream $TAG"; then
    cat <<EOF

  Conflicts during merge. Resolve them in your editor:
    1. Edit conflicted files (look for <<<<<<<).
    2. git add <files>
    3. git commit  (default message is fine)
    4. Then run: ./scripts/sync-upstream.sh --check-migrations $TAG

EOF
    exit 1
  fi
  echo
  echo "==> Merge clean. Run the migration check next:"
  echo "    ./scripts/sync-upstream.sh --check-migrations $TAG"
}

cmd_check() {
  echo "==> Pre-flight migration check for $TAG"
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" != "$SYNC_BRANCH" ]]; then
    echo "ERROR: must be on $SYNC_BRANCH (you're on $current_branch)" >&2
    exit 1
  fi

  # Find a backup to dry-run against
  local backup="${PROD_BACKUP:-}"
  if [[ -z "$backup" ]]; then
    if [[ -d "$UPLOAD_LOCATION/backups" ]]; then
      backup="$(find "$UPLOAD_LOCATION/backups" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.sql' \) -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)"
    fi
  fi
  if [[ -z "$backup" || ! -f "$backup" ]]; then
    cat <<EOF

  WARNING: no DB backup found at $UPLOAD_LOCATION/backups/.
  The pre-flight check needs a backup to dry-run migrations against.

  Options:
    1. Take one now from the running prod DB (recommended).
    2. Set PROD_BACKUP=/path/to/dump.sql.gz and re-run.
    3. Skip the check (DANGEROUS) — proceed straight to --finish.

EOF
    exit 1
  fi
  echo "  using backup: $backup"

  CONTAINER="immich_preflight_db_$$"
  cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  echo "==> Starting throwaway Postgres ($CONTAINER)"
  docker run --rm -d --name "$CONTAINER" \
    -e POSTGRES_PASSWORD=preflight \
    -e POSTGRES_DB=immich \
    -e POSTGRES_INITDB_ARGS=--data-checksums \
    "$PG_IMAGE" >/dev/null

  # Wait for Postgres
  for _ in $(seq 1 30); do
    if docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then break; fi
    sleep 1
  done

  echo "==> Restoring backup"
  if [[ "$backup" == *.gz ]]; then
    gunzip -c "$backup" | docker exec -i "$CONTAINER" psql -U postgres -d immich >/dev/null
  else
    docker exec -i "$CONTAINER" psql -U postgres -d immich < "$backup" >/dev/null
  fi

  echo "==> Comparing migrations"
  local applied
  applied="$(docker exec "$CONTAINER" psql -U postgres -d immich -tAc \
    "SELECT name FROM kysely_migrations ORDER BY name;" 2>/dev/null || true)"
  local in_repo
  in_repo="$(find "$REPO_ROOT/server/src/schema/migrations/" -maxdepth 1 -type f -name '*.ts' -printf '%f\n' | sed 's/\.ts$//' | sort)"
  local pending
  pending="$(comm -23 <(echo "$in_repo") <(echo "$applied"))"

  if [[ -z "$pending" ]]; then
    echo "  no pending migrations — DB schema already matches the new code"
  else
    echo "  pending migrations to be applied on deploy:"
    while IFS= read -r line; do echo "    $line"; done <<< "$pending"
    echo
    echo "  Scanning their up() bodies for destructive ops..."
    local destructive=0
    while IFS= read -r mig; do
      [[ -z "$mig" ]] && continue
      local file="$REPO_ROOT/server/src/schema/migrations/$mig.ts"
      [[ ! -f "$file" ]] && continue
      if grep -qiE 'dropColumn|dropTable|drop column|drop table|RENAME COLUMN' "$file"; then
        echo "    !! $mig contains destructive ops:"
        grep -niE 'dropColumn|dropTable|drop column|drop table|RENAME COLUMN' "$file" | sed 's/^/         /'
        destructive=1
      fi
    done <<< "$pending"
    if [[ "$destructive" -eq 1 ]]; then
      cat <<EOF

  DESTRUCTIVE migrations detected. Review them carefully.

  Choices:
    a) Accept the data loss and proceed to --finish.
    b) Patch the fork: add a fork-only migration BEFORE the destructive
       upstream one that preserves the data into a new table or column.
    c) Skip this sync: ./scripts/sync-upstream.sh --abort $TAG

EOF
      exit 1
    else
      echo "  no destructive ops. Safe to deploy."
    fi
  fi

  echo
  echo "==> Pre-flight passed. Next: --finish to merge into main"
  echo "    ./scripts/sync-upstream.sh --finish $TAG"
}

cmd_finish() {
  ensure_clean
  if ! git rev-parse "$SYNC_BRANCH" >/dev/null 2>&1; then
    echo "ERROR: $SYNC_BRANCH does not exist. Run --start first." >&2
    exit 1
  fi
  echo "==> Updating fork/upstream-baseline.txt"
  git checkout "$SYNC_BRANCH"
  echo "$TAG" > fork/upstream-baseline.txt
  if [[ -n "$(git status --porcelain fork/upstream-baseline.txt)" ]]; then
    git add fork/upstream-baseline.txt
    git commit -m "chore(fork): bump upstream baseline to $TAG"
  fi
  echo "==> Merging $SYNC_BRANCH into main"
  git checkout main
  git merge --no-ff "$SYNC_BRANCH" -m "merge $SYNC_BRANCH"
  echo "==> Pushing main"
  git push origin main
  echo "==> Deleting local $SYNC_BRANCH"
  git branch -d "$SYNC_BRANCH"
  cat <<EOF

  Sync complete. Next:
    1. Add a row to fork/changelog.md under '## Upstream syncs'.
    2. Cut the first personal release on the new baseline:
         ./scripts/release.sh

EOF
}

cmd_abort() {
  ensure_clean
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" == "$SYNC_BRANCH" ]]; then
    git checkout main
  fi
  if git rev-parse "$SYNC_BRANCH" >/dev/null 2>&1; then
    git branch -D "$SYNC_BRANCH"
    echo "Discarded $SYNC_BRANCH."
  else
    echo "$SYNC_BRANCH does not exist; nothing to abort."
  fi
}

case "$mode" in
  start)  cmd_start ;;
  check)  cmd_check ;;
  finish) cmd_finish ;;
  abort)  cmd_abort ;;
esac
