#!/usr/bin/env bash
# Re-vendor Upstream/ from the web repo at one commit.
#
#   scripts/upstream/sync.sh [sha]      (default: WEB_SHA from upstream.lock)
#
# Sparse, shallow fetch from GitHub of:
#   frontend/src/i18n/locales        -> Upstream/locales/<lang>/<ns>.json
#   frontend/design/tokens.json      -> Upstream/tokens.json
#   backend/app/telemetry/registry.py -> Upstream/registry.py
#   backend/tests/fixtures/alerts    -> Upstream/fixtures/alerts (golden cases)
# then exports Upstream/telemetry_registry.json (+ the TelemetryTests copy), writes
# Upstream/SOURCE and updates upstream.lock. Deterministic: the CI `tools` job re-runs
# it at the pinned SHA and fails if anything under Upstream/ changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/upstream.lock"

lock_value() { sed -n "s/^$1=//p" "$LOCK" | head -n 1; }

WEB_REPO="$(lock_value WEB_REPO)"
WEB_REPO="${WEB_REPO:-rupakc/travel-planner}"
SHA="${1:-$(lock_value WEB_SHA)}"

if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "sync.sh: need a full 40-hex commit SHA (got '${SHA}')" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git -C "$WORK" init -q
git -C "$WORK" remote add origin "https://github.com/${WEB_REPO}.git"
git -C "$WORK" sparse-checkout set --no-cone \
  '/frontend/src/i18n/locales/' \
  '/frontend/design/tokens.json' \
  '/backend/app/telemetry/registry.py' \
  '/backend/tests/fixtures/alerts/'
git -C "$WORK" fetch -q --depth 1 --filter=blob:none origin "$SHA"
git -C "$WORK" -c advice.detachedHead=false checkout -q FETCH_HEAD

SRC="$WORK"
for path in frontend/src/i18n/locales frontend/design/tokens.json backend/app/telemetry/registry.py backend/tests/fixtures/alerts; do
  [[ -e "$SRC/$path" ]] || { echo "sync.sh: $path missing at $SHA" >&2; exit 1; }
done
COMMIT_DATE="$(git -C "$WORK" show -s --format=%cI FETCH_HEAD)"

UP="$ROOT/Upstream"
rm -rf "$UP"
mkdir -p "$UP/locales"
( cd "$SRC/frontend/src/i18n/locales" && find . -type f -name '*.json' -print0 ) |
  while IFS= read -r -d '' file; do
    mkdir -p "$UP/locales/$(dirname "$file")"
    cp "$SRC/frontend/src/i18n/locales/$file" "$UP/locales/$file"
  done
cp "$SRC/frontend/design/tokens.json" "$UP/tokens.json"
cp "$SRC/backend/app/telemetry/registry.py" "$UP/registry.py"
mkdir -p "$UP/fixtures/alerts"
cp "$SRC"/backend/tests/fixtures/alerts/*.json "$UP/fixtures/alerts/"

python3 "$ROOT/tools/export_registry.py" "$UP/registry.py" "$UP/telemetry_registry.json"
TEST_COPY="$ROOT/Packages/VoyagerKit/Tests/TelemetryTests/Resources/telemetry_registry.json"
mkdir -p "$(dirname "$TEST_COPY")"
cp "$UP/telemetry_registry.json" "$TEST_COPY"

cat > "$UP/SOURCE" <<SOURCE
repo=${WEB_REPO}
sha=${SHA}
date=${COMMIT_DATE}
SOURCE

printf 'WEB_REPO=%s\nWEB_SHA=%s\n' "$WEB_REPO" "$SHA" > "$LOCK"

langs="$(find "$UP/locales" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
files="$(find "$UP/locales" -type f -name '*.json' | wc -l | tr -d ' ')"
echo "Upstream/ synced to ${WEB_REPO}@${SHA} (${COMMIT_DATE}): ${langs} languages, ${files} locale files"
