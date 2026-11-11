#!/usr/bin/env bash
# Build the app for the simulator (Debug, unsigned) and zip it to build/Voyager-sim.zip.
# Needs scripts/ci/generate.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
derived="$ROOT/build/DerivedData-sim"

xcodebuild build \
  -project Voyager.xcodeproj \
  -scheme Voyager \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO

app="$derived/Build/Products/Debug-iphonesimulator/Voyager.app"
[[ -d "$app" ]] || { echo "build-sim: $app was not produced" >&2; exit 1; }
rm -f "$ROOT/build/Voyager-sim.zip"
ditto -c -k --keepParent "$app" "$ROOT/build/Voyager-sim.zip"
echo "build-sim: build/Voyager-sim.zip"
