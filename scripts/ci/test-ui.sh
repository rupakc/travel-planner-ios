#!/usr/bin/env bash
# Run the XCUITest suite (scheme VoyagerUI) on a simulator.
#
#   scripts/ci/test-ui.sh iphone|ipad
#
# Until Task 38 adds the stub backend and the smoke flow, this runs the launch-only test.
# Writes build/ui-<device>.xcresult. Needs scripts/ci/generate.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
device="${1:?usage: test-ui.sh iphone|ipad}"

destination="$("$ROOT/scripts/ci/sim-destination.sh" "$device")"
mkdir -p "$ROOT/build"
result="$ROOT/build/ui-$device.xcresult"
rm -rf "$result"

cd "$ROOT"
xcodebuild test \
  -project Voyager.xcodeproj \
  -scheme VoyagerUI \
  -configuration Debug \
  -destination "$destination" \
  -resultBundlePath "$result" \
  -derivedDataPath "$ROOT/build/DerivedData-ui" \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipMacroValidation
