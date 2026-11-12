#!/usr/bin/env bash
# Boot one simulator and wait until it is fully up and responsive:
#
#   scripts/ci/sim-boot.sh <udid>
#
# Two facts from the CI logs (2026-11-12) shape this:
#   1. A healthy cold first boot of the iOS 26.0 runtime on GitHub's macos-15 arm64 runners takes 2-4 minutes
#      (137-260 s seen). A budget below that (the old 150 s) aborts healthy boots, and every retry is cold again.
#   2. Some boots of the iOS 26 runtime hang and never finish (still not up after 600-750 s, same device that boots
#      in 2-3 min on other runners); a known intermittent iOS 26 simulator problem, also seen on other CI providers.
#      Waiting longer does not help; shutting the device down, erasing it and booting again does.
# So: each attempt gets SIM_BOOT_ATTEMPT_TIMEOUT seconds (default 330, above a healthy cold boot); a hung attempt is
# shut down and erased, and booted again, up to SIM_BOOT_ATTEMPTS (default 2). The device is never deleted or
# recreated (the pinned UDID must stay valid for xcodebuild). When every attempt hangs this exits 1 loudly, with the
# device state CoreSimulator reports. Callers start it in the background while xcodebuild compiles.
set -euo pipefail

udid="${1:?usage: sim-boot.sh <udid>}"
attempt_timeout="${SIM_BOOT_ATTEMPT_TIMEOUT:-330}"
attempts="${SIM_BOOT_ATTEMPTS:-2}"
start=$SECONDS

# limited <seconds> <command...>: perl's alarm is the timeout macOS lacks.
limited() { local s="$1"; shift; perl -e "alarm $s; exec @ARGV" "$@"; }

# Every 30 s: the device state and whether its launchd answers, so a slow or stuck boot shows what it was doing.
watch_boot() {
  local t0=$1
  while sleep 30; do
    local state launchd=no
    state="$(limited 20 xcrun simctl list devices 2>/dev/null | grep -F "$udid" | grep -oE '\((Shutdown|Booting|Booted|Shutting Down)\)' || echo '(?)')"
    limited 20 xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1 && launchd=yes
    echo "sim-boot: [+$((SECONDS - t0))s] state $state launchd $launchd"
  done
}

for attempt in $(seq 1 "$attempts"); do
  t0=$SECONDS
  watch_boot "$t0" &
  watcher=$!
  # `bootstatus -b` boots the device itself and waits for the boot to complete (data migration included). Do not
  # `simctl boot` first: every green run booted this way, and a bootstatus attached to a device already booting was
  # seen to wait on a device CoreSimulator reported as Booted until the timeout.
  status=0
  limited "$attempt_timeout" xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || status=$?
  sleepers="$(pgrep -P "$watcher" 2>/dev/null || true)"
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  if [[ -n "$sleepers" ]]; then
    # shellcheck disable=SC2086
    kill $sleepers 2>/dev/null || true
  fi
  if [[ $status -eq 0 ]] && limited 60 xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1; then
    echo "sim-boot: $udid booted and responsive in $((SECONDS - t0))s (attempt $attempt, $((SECONDS - start))s total)"
    exit 0
  fi
  state="$(limited 30 xcrun simctl list devices 2>/dev/null | grep -F "$udid" | sed 's/^ *//' || true)"
  echo "::warning::sim-boot: attempt $attempt did not finish within ${attempt_timeout}s (status $status): ${state:-$udid not listed}"
  [[ $attempt -lt $attempts ]] || break
  echo "sim-boot: shutting down and erasing $udid, then booting again"
  limited 90 xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  limited 120 xcrun simctl erase "$udid" >/dev/null 2>&1 || true
done

echo "::error::sim-boot: $udid did not boot in $attempts attempt(s) of ${attempt_timeout}s ($((SECONDS - start))s total)"
exit 1
