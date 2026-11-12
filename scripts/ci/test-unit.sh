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
udid="${destination##*id=}"
mkdir -p "$ROOT/build"

result="$ROOT/build/unit-$device.xcresult"
log="$ROOT/build/unit-$device.log"
rm -rf "$result"

# Boot first, on an idle runner (scripts/ci/sim-boot.sh: bounded attempts, erase + one retry, fails loudly). A boot
# that overlapped the compile often wedged, and tests on a wedged simulator hang. sim-boot has its own time bound.
"$ROOT/scripts/ci/sim-boot.sh" "$udid"

args=(
  -scheme VoyagerKit-Package
  -destination "$destination"
  -derivedDataPath "$ROOT/build/DerivedData-unit"
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages"
  -onlyUsePackageVersionsFromResolvedFile
  -skipMacroValidation
  # Simulator builds are arm64 only (the runner is Apple silicon); building x86_64 too doubles the compile.
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=YES
)
test_args=(
  -resultBundlePath "$result"
  # The simulator is booted (bootstatus complete) before the build, so a test stuck for 4 minutes is a real hang;
  # the wall-clock watchdog below is the overall bound.
  # One test process on one simulator at a time: concurrent clones/destinations contend for CoreSimulator on a 3-core runner.
  -parallel-testing-enabled NO
  -disable-concurrent-destination-testing
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 240
  -maximum-test-execution-time-allowance 300
)
for filter in ${only//,/ }; do
  test_args+=("-only-testing:$filter")
done

# Hard wall-clock limit for the whole build + test run (UNIT_TIMEOUT seconds, default 1500): a simulator
# hang that test timeouts do not cover (for example while loading the runner) fails fast, not at 45 minutes.
# Output goes through a FIFO into `tee`, and the log is read only after tee has flushed it.
limit="${UNIT_TIMEOUT:-1500}"
flag="$(mktemp)"; rm -f "$flag"
fifo="$(mktemp -u)"; mkfifo "$fifo"
tee "$log" < "$fifo" &
tee_pid=$!
set +e
(
  cd "$ROOT/Packages/VoyagerKit"
  xcodebuild build-for-testing "${args[@]}" || exit
  exec xcodebuild test-without-building "${args[@]}" "${test_args[@]}"
) > "$fifo" 2>&1 &
pid=$!
( sleep "$limit"; touch "$flag"
  echo "::error::test-unit: exceeded ${limit}s; stopping xcodebuild (last output is in $log)"
  pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; sleep 15
  pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null ) &
watchdog=$!
wait "$pid"
status=$?
# Stop the watchdog subshell first (so it cannot go on to "time out"), then its orphaned sleep.
sleepers="$(pgrep -P "$watchdog" 2>/dev/null || true)"
kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
# shellcheck disable=SC2086
[[ -n "$sleepers" ]] && kill $sleepers 2>/dev/null
# tee ends when every writer has closed the FIFO; give stray children of a killed run a moment, then stop it.
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$tee_pid" 2>/dev/null || break; sleep 1; done
kill "$tee_pid" 2>/dev/null; wait "$tee_pid" 2>/dev/null
rm -f "$fifo"
set -e
if [[ -e "$flag" ]]; then status=124; rm -f "$flag"; fi

# Record runs (record_snapshots -> SNAPSHOT_RECORD=1): swift-snapshot-testing reports every snapshot it writes as a
# test failure ("... automatically recorded ..."). Such a run passes when those are its only errors.
if [[ $status -ne 0 && "${TEST_RUNNER_SNAPSHOT_RECORD:-}" == "1" ]]; then
  errors="$(grep -E ': error: ' "$log" | sort -u || true)"
  recorded="$(grep -ciE 'automatically recorded' <<<"$errors" || true)"
  others="$(grep -viE 'automatically recorded' <<<"$errors" | grep -c . || true)"
  if [[ $recorded -gt 0 && $others -eq 0 && $status -ne 124 ]]; then
    echo "::notice::test-unit: record run: $recorded snapshot(s) recorded (artifact \`snapshots\`); no other failures"
    status=0
  else
    echo "test-unit: record run has $others failure(s) besides recorded snapshots"
  fi
fi

warnings="$(grep -E ':[0-9]+(:[0-9]+)?: warning: ' "$log" |
  grep -F -e "$ROOT/Packages/VoyagerKit/Sources/" -e "$ROOT/App/" | sort -u || true)"
if [[ -n "$warnings" ]]; then
  echo "::error::Compiler warnings in project sources (zero warnings allowed):"
  echo "$warnings"
  [[ $status -eq 0 ]] && status=1
fi

exit "$status"
