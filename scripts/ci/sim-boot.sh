#!/usr/bin/env bash
# Boot one simulator and wait until it is fully up and responsive:
#
#   scripts/ci/sim-boot.sh <udid>
#
# One boot, one budget (SIM_BOOT_TIMEOUT seconds, default 600). A cold first boot of the iOS 26.0 runtime on
# GitHub's macos-15 arm64 runners takes about 2-4 minutes (it builds the dyld cache and migrates data), so a short
# budget plus "shutdown, erase, retry" restarts a cold boot from zero every time and never finishes. Nothing here
# erases, deletes or recreates a device: when the boot does not finish, this prints what CoreSimulator reports and
# exits 1, so the caller fails loudly instead of pointing xcodebuild at a device that is not there.
# Callers start it in the background while xcodebuild compiles, then `wait` for it.
set -euo pipefail

udid="${1:?usage: sim-boot.sh <udid>}"
budget="${SIM_BOOT_TIMEOUT:-600}"
start=$SECONDS

# "Unable to boot device in current state: Booted" is fine; any other boot error shows up in bootstatus below.
xcrun simctl boot "$udid" 2>&1 | grep -v "current state: Booted" || true

# perl's alarm is the timeout macOS lacks; bootstatus -b waits for the boot to complete (data migration included).
if perl -e "alarm $budget; exec @ARGV" xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 &&
   # A booted but wedged device does not answer a launchd query.
   perl -e 'alarm 60; exec @ARGV' xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1; then
  echo "sim-boot: $udid booted and responsive in $((SECONDS - start))s"
  exit 0
fi

echo "::error::sim-boot: $udid did not finish booting within ${budget}s (elapsed $((SECONDS - start))s)"
xcrun simctl list devices | grep -F "$udid" || echo "sim-boot: $udid is not listed by simctl"
perl -e 'alarm 20; exec @ARGV' xcrun simctl bootstatus "$udid" 2>&1 | tail -5 || true
exit 1
