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

# Boot the simulator and prove it is responsive before xcodebuild uses it. On macOS runners a simulator whose boot
# never completes (bootstatus still waiting after 5 minutes) makes the FIRST UIKit-touching test hang for its whole
# time allowance, and xcodebuild's relaunch then hangs again on the same wedged device. So a boot that does not
# finish in 150 s is reset (shutdown, erase) and retried, and the last attempt uses a freshly created device.
udid="${destination##*id=}"
boot_sim() {
  perl -e 'alarm 150; exec @ARGV' xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || return 1
  # Responsive probe: a booted-but-wedged device does not answer a launchd query.
  perl -e 'alarm 30; exec @ARGV' xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1 || return 1
}
booted=0
for attempt in 1 2 3; do
  if boot_sim; then booted=1; break; fi
  echo "test-unit: simulator boot attempt $attempt did not finish; resetting"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  if [[ $attempt -lt 2 ]]; then
    xcrun simctl erase "$udid" >/dev/null 2>&1 || true
  else
    runtime="$(xcrun simctl list devices -j | U="$udid" python3 -c "
import json,sys,os
u=os.environ['U']
for r,ds in json.load(sys.stdin)['devices'].items():
    for d in ds:
        if d['udid']==u: print(r, d['name'])" 2>/dev/null || true)"
    runtime_id="${runtime%% *}"; dev_name="${runtime#* }"
    if [[ -n "$runtime_id" ]]; then
      xcrun simctl delete "$udid" >/dev/null 2>&1 || true
      new="$(xcrun simctl create "voyager-ci-$attempt" "$dev_name" "$runtime_id" 2>/dev/null || true)"
      if [[ -n "$new" ]]; then udid="$new"; destination="platform=iOS Simulator,id=$udid"; fi
    fi
  fi
done
[[ $booted -eq 1 ]] || echo "test-unit: simulator never became responsive; continuing (tests may stall)"
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
  # The simulator is proven responsive above, so a test stuck for 4 minutes is a real hang (a freeze of 130-200 s
  # was seen on cold devices); the wall-clock watchdog below is the overall bound.
  # One test process on one simulator at a time: concurrent clones/destinations contend for CoreSimulator on a 3-core runner.
  -parallel-testing-enabled NO
  -disable-concurrent-destination-testing
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 240
  -maximum-test-execution-time-allowance 300
)
for filter in ${only//,/ }; do
  args+=("-only-testing:$filter")
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
(cd "$ROOT/Packages/VoyagerKit" && exec xcodebuild "${args[@]}") > "$fifo" 2>&1 &
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

warnings="$(grep -E ':[0-9]+(:[0-9]+)?: warning: ' "$log" |
  grep -F -e "$ROOT/Packages/VoyagerKit/Sources/" -e "$ROOT/App/" | sort -u || true)"
if [[ -n "$warnings" ]]; then
  echo "::error::Compiler warnings in project sources (zero warnings allowed):"
  echo "$warnings"
  [[ $status -eq 0 ]] && status=1
fi
exit "$status"
