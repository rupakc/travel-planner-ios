#!/usr/bin/env bash
# Boot one simulator and wait until it is fully up and responsive:
#
#   scripts/ci/sim-boot.sh <udid>
#
# What the CI logs (2026-11-12) showed, and why this does not simply wait for `simctl bootstatus -b`:
#   1. A healthy cold first boot of the iOS 26.0 runtime on GitHub's macos-15 arm64 runners takes 2-4 minutes
#      (120-260 s seen). A budget below that (the old 150 s) aborts healthy boots, and every retry is cold again.
#   2. `bootstatus -b` sometimes never returns although CoreSimulator reports the device Booted and its launchd
#      answers (run 43282252543: Booted + responsive from +45 s, bootstatus still waiting at 330 s). Waiting on
#      bootstatus alone was why "the simulator never boots".
# So the device is ready when bootstatus returns, or when it has been Booted with a responsive launchd for
# SIM_READY_POLLS consecutive polls (default 4, every 15 s), whichever comes first. An attempt that reaches neither
# within SIM_BOOT_ATTEMPT_TIMEOUT seconds (default 330) is shut down, erased and booted again, up to
# SIM_BOOT_ATTEMPTS (default 2). The device is never deleted or recreated (the pinned UDID must stay valid for
# xcodebuild). When every attempt fails this exits 1 loudly. Callers start it in the background during the build.
set -euo pipefail

udid="${1:?usage: sim-boot.sh <udid>}"
attempt_timeout="${SIM_BOOT_ATTEMPT_TIMEOUT:-330}"
attempts="${SIM_BOOT_ATTEMPTS:-2}"
start=$SECONDS

# limited <seconds> <command...>: perl's alarm is the timeout macOS lacks.
limited() { local s="$1"; shift; perl -e "alarm $s; exec @ARGV" "$@"; }

ready_polls="${SIM_READY_POLLS:-4}"
poll="${SIM_POLL_SECONDS:-15}"

# device_state: Booted, Booting, Shutdown, ... or "?" when simctl does not answer in time.
device_state() {
  limited 30 xcrun simctl list devices 2>/dev/null | grep -F "$udid" |
    grep -oE '\((Shutdown|Booting|Booted|Shutting Down)\)' | tr -d '()' || echo "?"
}

for attempt in $(seq 1 "$attempts"); do
  t0=$SECONDS
  # `bootstatus -b` boots the device and waits for the boot to complete (data migration included).
  # perl directly (not the shell function) so $! is bootstatus itself and `kill` reaches it.
  perl -e "alarm $attempt_timeout; exec @ARGV" xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 &
  bootstatus=$!
  streak=0
  ready=""
  while (( SECONDS - t0 < attempt_timeout )); do
    sleep "$poll"
    if ! kill -0 "$bootstatus" 2>/dev/null; then
      status=0
      wait "$bootstatus" || status=$?
      [[ $status -eq 0 ]] && { ready="bootstatus reported the boot complete"; break; }
      [[ $status -eq 142 ]] && break # bootstatus ran out of the attempt's time
      echo "sim-boot: bootstatus exited with status $status; going by the device state"
    fi
    state="$(device_state)"
    launchd=no
    limited 30 xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1 && launchd=yes
    echo "sim-boot: [+$((SECONDS - t0))s] state $state launchd $launchd"
    if [[ $state == Booted && $launchd == yes ]]; then streak=$((streak + 1)); else streak=0; fi
    if (( streak >= ready_polls )); then
      ready="Booted and responsive for $streak polls (bootstatus had not returned)"
      break
    fi
  done
  kill "$bootstatus" 2>/dev/null || true
  wait "$bootstatus" 2>/dev/null || true
  if [[ -n "$ready" ]]; then
    echo "sim-boot: $udid ready after $((SECONDS - t0))s (attempt $attempt, $((SECONDS - start))s total): $ready"
    exit 0
  fi
  echo "::warning::sim-boot: attempt $attempt: $udid not ready within ${attempt_timeout}s (state $(device_state))"
  [[ $attempt -lt $attempts ]] || break
  echo "sim-boot: shutting down and erasing $udid, then booting again"
  limited 90 xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  limited 120 xcrun simctl erase "$udid" >/dev/null 2>&1 || true
done

echo "::error::sim-boot: $udid did not boot in $attempts attempt(s) of ${attempt_timeout}s ($((SECONDS - start))s total)"
exit 1
