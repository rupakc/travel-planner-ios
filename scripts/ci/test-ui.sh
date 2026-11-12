#!/usr/bin/env bash
# Run the XCUITest suite (scheme VoyagerUI) on one or more pinned simulators, building once:
#
#   scripts/ci/test-ui.sh iphone [ipad]
#
# Until Task 38 adds the stub backend and the smoke flow, this runs the launch-only test.
# Writes build/ui-<device>.xcresult per device. Needs scripts/ci/generate.sh first.
#
# The simulators boot one after another BEFORE the build (scripts/ci/sim-boot.sh: bounded attempts, erase + one
# retry): a boot that overlapped the compile on a 3-core runner often wedged, and boots on an idle runner did not. Each device's run has a hard wall-clock limit
# (UI_ATTEMPT_TIMEOUT, default 300 s; a healthy run takes 100-160 s), because a hang while launching the runner is not covered by test timeouts.
# All devices run even when one fails; the script fails if any did.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ $# -ge 1 ]] || { echo "usage: test-ui.sh iphone [ipad]" >&2; exit 2; }
attempt_timeout="${UI_ATTEMPT_TIMEOUT:-300}"
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
  # Simulator builds are arm64 only (the runner is Apple silicon); building x86_64 too doubles the compile.
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=YES
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
done
declare -a booted
for i in "${!devices[@]}"; do
  status=0
  "$ROOT/scripts/ci/sim-boot.sh" "${destinations[$i]##*id=}" || status=$?
  booted+=("$status")
done

xcodebuild build-for-testing "${common[@]}" -destination 'generic/platform=iOS Simulator'

failed=0
for i in "${!devices[@]}"; do
  device="${devices[$i]}"
  result="$ROOT/build/ui-$device.xcresult"
  rm -rf "$result"
  if [[ ${booted[$i]} -ne 0 ]]; then
    echo "::error::test-ui: $device simulator did not boot; not running its tests"
    failed=1
    continue
  fi
  echo "test-ui: $device on ${destinations[$i]}"
  udid="${destinations[$i]##*id=}"
  # Warm up: on a freshly created iOS 18.6 device the FIRST host-initiated app launch (xcodebuild launching the
  # UI-test runner) was sometimes never delivered to SpringBoard, so xcodebuild waited silently until the watchdog
  # (runs 43307335383, 43322096480; no RBSLaunchRequest for the runner in the simulator log). A `simctl launch` of a
  # system app first makes the path work (run 43317210574: 25 s and 6 s, then both devices ran their tests).
  t0=$SECONDS
  wstatus=0
  perl -e 'alarm 120; exec @ARGV' xcrun simctl launch "$udid" com.apple.Preferences >/dev/null 2>&1 || wstatus=$?
  echo "test-ui: warm-up launch on $device: status $wstatus after $((SECONDS - t0))s"
  perl -e 'alarm 30; exec @ARGV' xcrun simctl terminate "$udid" com.apple.Preferences >/dev/null 2>&1 || true
  # Simulator log for this run (uploaded with the xcresult on failure).
  xcrun simctl spawn "$udid" log stream --style compact \
    --predicate 'process IN {"SpringBoard","runningboardd","testmanagerd","CoreSimulatorBridge","VoyagerUITests-Runner","Voyager"} OR subsystem BEGINSWITH "com.apple.FrontBoard"' \
    > "$ROOT/build/ui-$device-sim.log" 2>&1 &
  logpid=$!
  status=0
  run_limited "$attempt_timeout" xcodebuild test-without-building "${common[@]}" \
    -destination "${destinations[$i]}" \
    -resultBundlePath "$result" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 300 || status=$?
  kill "$logpid" 2>/dev/null || true
  if [[ $status -ne 0 ]]; then
    echo "::error::test-ui: $device failed (status $status)"
    failed=1
  fi
done
exit "$failed"
