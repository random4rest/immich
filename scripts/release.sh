#!/usr/bin/env bash
#
# release.sh — tag and build a personal Immich release.
#
# Reads fork/upstream-baseline.txt for the upstream tag (e.g. v2.7.5),
# finds the highest existing vX.Y.Z-personal.N tag, bumps N, builds the
# server image with --build-arg BUILD_ID set (SvelteKit hash bug fix),
# and pushes the git tag.
#
# Usage:
#   ./scripts/release.sh                  interactive; bumps personal counter
#   ./scripts/release.sh --no-push        build + tag locally, don't push
#   ./scripts/release.sh --dry-run        print what would happen, change nothing
#   ./scripts/release.sh --yes            skip confirmation prompts
#
# See fork/release.md for full documentation.

set -euo pipefail

# Resolve repo root from script location so this works no matter where it's run from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=0
NO_PUSH=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-push) NO_PUSH=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --help|-h)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $arg"; exit 2 ;;
  esac
done

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY RUN: $*"
  else
    eval "$@"
  fi
}

# Confirm we're on main with a clean tree
current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" != "main" ]]; then
  echo "ERROR: must be on main; you're on '$current_branch'" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is dirty:" >&2
  git status --short >&2
  exit 1
fi

# Read upstream baseline
baseline_file="$REPO_ROOT/fork/upstream-baseline.txt"
if [[ ! -f "$baseline_file" ]]; then
  echo "ERROR: $baseline_file not found" >&2
  exit 1
fi
UPSTREAM_TAG="$(cat "$baseline_file" | tr -d '[:space:]')"
if ! [[ "$UPSTREAM_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: $baseline_file does not contain a valid tag (got: '$UPSTREAM_TAG')" >&2
  exit 1
fi

# Compute next personal counter for this baseline
existing_max="$(git tag --list "${UPSTREAM_TAG}-personal.*" \
  | sed -E "s/^${UPSTREAM_TAG}-personal\.//" \
  | grep -E '^[0-9]+$' \
  | sort -n \
  | tail -1 || true)"
NEXT_N=$(( ${existing_max:-0} + 1 ))
VERSION="${UPSTREAM_TAG}-personal.${NEXT_N}"

# Check it doesn't already exist (paranoia)
if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "ERROR: tag $VERSION already exists" >&2
  exit 1
fi

cat <<EOF

  upstream baseline: $UPSTREAM_TAG
  highest existing:  ${existing_max:+${UPSTREAM_TAG}-personal.${existing_max}}${existing_max:-(none)}
  about to release:  $VERSION
  HEAD:              $(git rev-parse --short HEAD)  $(git log -1 --pretty=format:'%s')

EOF

if [[ "$ASSUME_YES" != "1" && "$DRY_RUN" != "1" ]]; then
  read -r -p "Build and tag $VERSION? [y/N] " ans
  if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    echo "aborted"
    exit 0
  fi
fi

# Build the server image with stable BUILD_ID
echo
echo "==> Building immich-server:$VERSION"
run "docker build \
  -t 'immich-server:$VERSION' \
  --build-arg BUILD_ID='$VERSION' \
  -f server/Dockerfile ."

# SvelteKit hash sanity check — only if not dry-run
if [[ "$DRY_RUN" != "1" ]]; then
  echo
  echo "==> SvelteKit hash sanity check"
  hashes=$(docker run --rm --entrypoint sh "immich-server:$VERSION" -c '
    grep -o "__sveltekit_[a-z0-9]*" /build/www/index.html | sort -u
    grep -rho "globalThis.__sveltekit_[a-z0-9]*" /build/www/_app | sed "s/globalThis\\.//" | sort -u
  ' | sort -u)
  count=$(echo "$hashes" | wc -l)
  if [[ "$count" -ne 1 ]]; then
    echo "ERROR: SvelteKit hash mismatch in built image:" >&2
    echo "$hashes" >&2
    echo "Image will spinner-of-death the web client. Aborting; image kept for inspection." >&2
    exit 1
  fi
  echo "  $hashes  (single hash, OK)"
fi

# Tag + push
echo
echo "==> Tagging $VERSION"
run "git tag -a '$VERSION' -m 'release $VERSION'"

if [[ "$NO_PUSH" == "1" ]]; then
  echo
  echo "  --no-push set; not pushing tag. To push later:"
  echo "    git push origin '$VERSION'"
else
  echo
  echo "==> Pushing tag to origin"
  run "git push origin '$VERSION'"
fi

cat <<EOF

  Released: $VERSION
  Image:    immich-server:$VERSION  (local Docker daemon)
  Git tag:  $VERSION  $(if [[ "$NO_PUSH" == "1" ]]; then echo '(local only)'; else echo '(pushed to origin)'; fi)

  To deploy:
    cd ~/Projects/immich/immich-app
    \$EDITOR .env       # set IMMICH_VERSION=$VERSION
    ./scripts/deploy.sh

EOF
