#!/usr/bin/env bash
# Regenerate generated sources (when their generators exist), then Voyager.xcodeproj.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

for gen in tools/gen_tokens.py tools/gen_catalog.py; do
  if [[ -f "$gen" ]]; then
    echo "generate: $gen"
    python3 "$gen"
  fi
done

xcodegen generate --spec project.yml --quiet

# Resolve the app's packages exactly like the package itself (one Package.resolved, committed).
RESOLVED_DIR="Voyager.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RESOLVED_DIR"
cp Packages/VoyagerKit/Package.resolved "$RESOLVED_DIR/Package.resolved"
echo "generate: Voyager.xcodeproj"
