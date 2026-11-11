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

# Boot the simulator and wait until its system services are up before the first test touches
# fonts, assets or preferences (a cold-booting simulator stalled a whole test run for minutes).
udid="${destination##*id=}"
perl -e 'alarm 300; exec @ARGV' xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 ||
  echo "test-unit: simulator warm-up did not finish (continuing)"
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
  # A hung test fails in minutes instead of holding the runner until the job timeout.
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 120
  -maximum-test-execution-time-allowance 300
)
for filter in ${only//,/ }; do
  args+=("-only-testing:$filter")
done

# Hard wall-clock limit for the whole build + test run (UNIT_TIMEOUT seconds, default 1500): a simulator
# hang that test timeouts do not cover (for example while loading the runner) fails fast, not at 45 minutes.
limit="${UNIT_TIMEOUT:-1500}"
flag="$(mktemp)"; rm -f "$flag"
set +e
(cd "$ROOT/Packages/VoyagerKit" && exec xcodebuild "${args[@]}") > >(tee "$log") 2>&1 &
pid=$!
( sleep "$limit"; touch "$flag"
  echo "::error::test-unit: exceeded ${limit}s; stopping xcodebuild (last output is in $log)"
  pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; sleep 15
  pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null ) &
watchdog=$!
wait "$pid"
status=$?
kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
set -e
if [[ -e "$flag" ]]; then status=124; rm -f "$flag"; fi

warnings="$(grep -E ':[0-9]+(:[0-9]+)?: warning: ' "$log" |
  grep -F -e "$ROOT/Packages/VoyagerKit/Sources/" -e "$ROOT/App/" | sort -u || true)"
if [[ -n "$warnings" ]]; then
  echo "::error::Compiler warnings in project sources (zero warnings allowed):"
  echo "$warnings"
  [[ $status -eq 0 ]] && status=1
fi
exit "$status"
