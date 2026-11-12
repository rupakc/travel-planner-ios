#!/usr/bin/env bash
# Run the XCUITest suite (scheme VoyagerUI) on one or more pinned simulators, building once:
#
#   scripts/ci/test-ui.sh iphone [ipad]
#
# Until Task 38 adds the stub backend and the smoke flow, this runs the launch-only test.
# Writes build/ui-<device>.xcresult per device. Needs scripts/ci/generate.sh first.
#
# Every simulator starts booting (scripts/ci/sim-boot.sh: one boot, its own budget) while the app and the UI test
# runner compile, so the 2-4 minute cold boot overlaps the build. Each device's run has a hard wall-clock limit
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
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  if [[ -e "$flag" ]]; then status=124; rm -f "$flag"; fi
  return "$status"
}

declare -a devices destinations boot_pids
for device in "$@"; do
  destination="$("$ROOT/scripts/ci/sim-destination.sh" "$device")"
  "$ROOT/scripts/ci/sim-boot.sh" "${destination##*id=}" > "$ROOT/build/boot-$device.log" 2>&1 &
  devices+=("$device"); destinations+=("$destination"); boot_pids+=($!)
done

xcodebuild build-for-testing "${common[@]}" -destination 'generic/platform=iOS Simulator'

failed=0
for i in "${!devices[@]}"; do
  device="${devices[$i]}"
  result="$ROOT/build/ui-$device.xcresult"
  rm -rf "$result"
  boot_status=0
  wait "${boot_pids[$i]}" || boot_status=$?
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
exit "$failed"
