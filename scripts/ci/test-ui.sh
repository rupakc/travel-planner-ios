#!/usr/bin/env bash
# Run the XCUITest suite (scheme VoyagerUI) on one or more pinned simulators, building once:
#
#   scripts/ci/test-ui.sh iphone [ipad]
#
# Until Task 38 adds the stub backend and the smoke flow, this runs the launch-only test.
# Writes build/ui-<device>.xcresult per device. Needs scripts/ci/generate.sh first.
#
# The simulators boot one after another (scripts/ci/sim-boot.sh: one boot, its own budget) in the background while
# the app and the UI test runner compile, so the 2-4 minute cold boots overlap the build. Not at the same time: two
# cold boots plus the compile on a 3-core runner starved one boot past 10 minutes (run 43262978658). Each device's run has a hard wall-clock limit
# (UI_ATTEMPT_TIMEOUT, default 480 s), because a hang while launching the runner is not covered by test timeouts.
# All devices run even when one fails; the script fails if any did.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ $# -ge 1 ]] || { echo "usage: test-ui.sh iphone [ipad]" >&2; exit 2; }
attempt_timeout="${UI_ATTEMPT_TIMEOUT:-480}"
derived="$ROOT/build/DerivedData-ui"
mkdir -p "$ROOT/build"
cd "$ROOT"

common=(
  -project Voyager.xcodeproj
  -scheme VoyagerUI
  -configuration Debug
  -derivedDataPath "$derived"
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages"
  -onlyUsePackageVersionsFromResolvedFile
  -skipMacroValidation
)

# run_limited <seconds> <command...>: the command's status, or 124 when it ran out of time.
run_limited() {
  local limit="$1"; shift
  local flag
  flag="$(mktemp)"; rm -f "$flag"
  "$@" &
  local pid=$!
  ( sleep "$limit"; touch "$flag"
    echo "::error::test-ui: run exceeded ${limit}s; stopping xcodebuild"
    kill -TERM "$pid" 2>/dev/null; sleep 15; kill -KILL "$pid" 2>/dev/null ) &
  local watchdog=$!
  local status=0
  wait "$pid" || status=$?
  # Stop the watchdog and its sleep (an orphaned sleep would hold the step's output open).
  local sleepers
  sleepers="$(pgrep -P "$watchdog" 2>/dev/null || true)"
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  if [[ -n "$sleepers" ]]; then
    # shellcheck disable=SC2086
    kill $sleepers 2>/dev/null || true
  fi
  if [[ -e "$flag" ]]; then status=124; rm -f "$flag"; fi
  return "$status"
}

declare -a devices destinations
for device in "$@"; do
  destinations+=("$("$ROOT/scripts/ci/sim-destination.sh" "$device")"); devices+=("$device")
  rm -f "$ROOT/build/boot-$device.status"
done
# Boot chain: build/boot-<device>.log, then build/boot-<device>.status (sim-boot's exit status) once it is done.
(
  for i in "${!devices[@]}"; do
    status=0
    "$ROOT/scripts/ci/sim-boot.sh" "${destinations[$i]##*id=}" > "$ROOT/build/boot-${devices[$i]}.log" 2>&1 || status=$?
    echo "$status" > "$ROOT/build/boot-${devices[$i]}.status"
  done
) &
boot_chain=$!

xcodebuild build-for-testing "${common[@]}" -destination 'generic/platform=iOS Simulator'

failed=0
for i in "${!devices[@]}"; do
  device="${devices[$i]}"
  result="$ROOT/build/ui-$device.xcresult"
  rm -rf "$result"
  while [[ ! -s "$ROOT/build/boot-$device.status" ]] && kill -0 "$boot_chain" 2>/dev/null; do sleep 2; done
  boot_status="$(cat "$ROOT/build/boot-$device.status" 2>/dev/null || echo 1)"
  cat "$ROOT/build/boot-$device.log"
  if [[ $boot_status -ne 0 ]]; then
    echo "::error::test-ui: $device simulator did not boot; not running its tests"
    failed=1
    continue
  fi
  echo "test-ui: $device on ${destinations[$i]}"
  status=0
  run_limited "$attempt_timeout" xcodebuild test-without-building "${common[@]}" \
    -destination "${destinations[$i]}" \
    -resultBundlePath "$result" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 300 || status=$?
  if [[ $status -ne 0 ]]; then
    echo "::error::test-ui: $device failed (status $status)"
    failed=1
  fi
done
wait "$boot_chain" 2>/dev/null || true
exit "$failed"
