#!/usr/bin/env bash
# Run the VoyagerKit package tests on a simulator.
#
#   scripts/ci/test-unit.sh iphone|ipad [only_testing]
#
# only_testing: comma- or space-separated xcodebuild -only-testing: values
# (`DomainTests`, `DomainTests/ItineraryLayoutTests`); empty runs everything.
# Writes build/unit-<device>.xcresult and build/unit-<device>.log. Fails when the build log
# has a compiler warning from a file under Packages/VoyagerKit/Sources or App (package
# targets cannot set -warnings-as-errors).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
device="${1:?usage: test-unit.sh iphone|ipad [only_testing]}"
only="${2:-}"

destination="$("$ROOT/scripts/ci/sim-destination.sh" "$device")"
mkdir -p "$ROOT/build"
result="$ROOT/build/unit-$device.xcresult"
log="$ROOT/build/unit-$device.log"
rm -rf "$result"

args=(
  test
  -scheme VoyagerKit-Package
  -destination "$destination"
  -resultBundlePath "$result"
  -derivedDataPath "$ROOT/build/DerivedData-unit"
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages"
  -onlyUsePackageVersionsFromResolvedFile
  -skipMacroValidation
)
for filter in ${only//,/ }; do
  args+=("-only-testing:$filter")
done

set +e
(cd "$ROOT/Packages/VoyagerKit" && xcodebuild "${args[@]}") 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e

warnings="$(grep -E ':[0-9]+(:[0-9]+)?: warning: ' "$log" |
  grep -F -e "$ROOT/Packages/VoyagerKit/Sources/" -e "$ROOT/App/" | sort -u || true)"
if [[ -n "$warnings" ]]; then
  echo "::error::Compiler warnings in project sources (zero warnings allowed):"
  echo "$warnings"
  [[ $status -eq 0 ]] && status=1
fi
exit "$status"
