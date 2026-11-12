#!/usr/bin/env bash
# Boot one simulator and wait until it is fully up and responsive:
#
#   scripts/ci/sim-boot.sh <udid>
#
# What the CI logs (2026-11-12) showed:
#   1. A healthy cold first boot of the iOS 26.0 runtime on GitHub's macos-15 arm64 runners takes 2-4 minutes
#      (120-260 s seen). A budget below that (the old 150 s) aborts healthy boots, and every retry is cold again.
#   2. Booting while xcodebuild compiles (3-core runner) wedged the iPhone boot in 5 of 7 tries: CoreSimulator said
#      Booted and launchd answered, but `bootstatus -b` never returned, and UIKit tests run on it hung for their whole
#      time allowance. Boots on an idle runner were fine. So callers boot BEFORE building, and only `bootstatus`
#      returning means ready ("Booted" alone does not).
# Each attempt gets SIM_BOOT_ATTEMPT_TIMEOUT seconds (default 330); one that does not finish is shut down, erased and
# booted again, up to SIM_BOOT_ATTEMPTS (default 2). The device is never deleted or recreated (the pinned UDID must
# stay valid for xcodebuild). When every attempt fails this exits 1 loudly. The state is logged every 30 s.
set -euo pipefail

udid="${1:?usage: sim-boot.sh <udid>}"
attempt_timeout="${SIM_BOOT_ATTEMPT_TIMEOUT:-330}"
attempts="${SIM_BOOT_ATTEMPTS:-2}"
start=$SECONDS

# limited <seconds> <command...>: perl's alarm is the timeout macOS lacks.
limited() { local s="$1"; shift; perl -e "alarm $s; exec @ARGV" "$@"; }

# device_state: Booted, Booting, Shutdown, ... or "?" when simctl does not answer in time.
device_state() {
  limited 30 xcrun simctl list devices 2>/dev/null | grep -F "$udid" |
    grep -oE '\((Shutdown|Booting|Booted|Shutting Down)\)' | tr -d '()' || echo "?"
}

for attempt in $(seq 1 "$attempts"); do
  t0=$SECONDS
  # `bootstatus -b` boots the device and waits for the boot to complete (data migration included). perl directly
  # (not the shell function) so $! is bootstatus itself.
  perl -e "alarm $attempt_timeout; exec @ARGV" xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 &
  bootstatus=$!
  status=""
  while [[ -z "$status" ]]; do
    for _ in $(seq 1 "${SIM_POLL_SECONDS:-30}"); do
      kill -0 "$bootstatus" 2>/dev/null || break
      sleep 1
    done
    if ! kill -0 "$bootstatus" 2>/dev/null; then
      status=0
      wait "$bootstatus" || status=$?
    else
      echo "sim-boot: [+$((SECONDS - t0))s] state $(device_state), bootstatus still waiting"
    fi
  done
  if [[ $status -eq 0 ]] && limited 60 xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1; then
    echo "sim-boot: $udid booted and responsive in $((SECONDS - t0))s (attempt $attempt, $((SECONDS - start))s total)"
    exit 0
  fi
  echo "::warning::sim-boot: attempt $attempt: $udid not booted within ${attempt_timeout}s (bootstatus status $status, state $(device_state))"
  [[ $attempt -lt $attempts ]] || break
  echo "sim-boot: shutting down and erasing $udid, then booting again"
  limited 90 xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  limited 120 xcrun simctl erase "$udid" >/dev/null 2>&1 || true
done

echo "::error::sim-boot: $udid did not boot in $attempts attempt(s) of ${attempt_timeout}s ($((SECONDS - start))s total)"
exit 1
