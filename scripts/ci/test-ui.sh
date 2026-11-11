#!/usr/bin/env bash
# Run the XCUITest suite (scheme VoyagerUI) on a simulator.
#
#   scripts/ci/test-ui.sh iphone|ipad
#
# Until Task 38 adds the stub backend and the smoke flow, this runs the launch-only test.
# Writes build/ui-<device>.xcresult. Needs scripts/ci/generate.sh first.
#
# Fails fast instead of hanging: the simulator is booted up front, the tests run with
# xcodebuild's test timeouts, and each attempt has a hard wall-clock limit (UI_ATTEMPT_TIMEOUT,
# default 480 s), because a hang while launching the runner is not covered by test timeouts.
# A failed or timed-out attempt is retried once on an erased, freshly booted simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
device="${1:?usage: test-ui.sh iphone|ipad}"
attempt_timeout="${UI_ATTEMPT_TIMEOUT:-480}"

destination="$("$ROOT/scripts/ci/sim-destination.sh" "$device")"
udid="${destination##*id=}"
mkdir -p "$ROOT/build"
result="$ROOT/build/ui-$device.xcresult"
derived="$ROOT/build/DerivedData-ui"
cd "$ROOT"

common=(
  -project Voyager.xcodeproj
  -scheme VoyagerUI
  -configuration Debug
  -destination "$destination"
  -derivedDataPath "$derived"
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages"
  -onlyUsePackageVersionsFromResolvedFile
  -skipMacroValidation
)

boot() {
  xcrun simctl boot "$udid" 2>/dev/null || true # already booted is fine
  xcrun simctl bootstatus "$udid" -b
}

# run_limited <seconds> <command...>: the command's status, or 124 when it ran out of time.
run_limited() {
  local limit="$1"; shift
  local flag
  flag="$(mktemp)"; rm -f "$flag"
  "$@" &
  local pid=$!
  ( sleep "$limit"; touch "$flag"
    echo "::error::test-ui: attempt exceeded ${limit}s; stopping xcodebuild"
    kill -TERM "$pid" 2>/dev/null; sleep 15; kill -KILL "$pid" 2>/dev/null ) &
  local watchdog=$!
  local status=0
  wait "$pid" || status=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  if [[ -e "$flag" ]]; then status=124; rm -f "$flag"; fi
  return "$status"
}

echo "test-ui: booting $udid"
boot
xcodebuild build-for-testing "${common[@]}"

for attempt in 1 2; do
  rm -rf "$result"
  echo "test-ui: attempt $attempt on $udid"
  status=0
  run_limited "$attempt_timeout" xcodebuild test-without-building "${common[@]}" \
    -resultBundlePath "$result" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 300 || status=$?
  [[ $status -eq 0 ]] && exit 0
  echo "::warning::test-ui: attempt $attempt failed (status $status)"
  [[ $attempt -eq 2 ]] && exit "$status"
  echo "test-ui: retrying on an erased simulator"
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  xcrun simctl erase "$udid"
  boot
done
