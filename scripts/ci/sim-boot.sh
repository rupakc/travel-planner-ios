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
echo "sim-boot: $udid simctl boot returned after $((SECONDS - start))s; waiting for the boot to complete"

# bootstatus -b waits for the boot to complete (data migration included) and prints each stage it waits on; each
# new stage is logged with the elapsed time, so a stalled boot shows where it stalled. perl's alarm is the timeout
# macOS lacks; the budget counts from the start of this script.
remaining=$((budget - (SECONDS - start))); (( remaining > 30 )) || remaining=30
set +e
perl -e "alarm $remaining; exec @ARGV" xcrun simctl bootstatus "$udid" -b 2>&1 |
  { prev=""; while IFS= read -r line; do
      [[ "$line" == "$prev" ]] || echo "sim-boot: [+$((SECONDS - start))s] $line"; prev="$line"
    done; }
booted=${PIPESTATUS[0]}
set -e

# A booted but wedged device does not answer a launchd query.
if [[ $booted -eq 0 ]] &&
   perl -e 'alarm 60; exec @ARGV' xcrun simctl spawn "$udid" launchctl print system >/dev/null 2>&1; then
  echo "sim-boot: $udid booted and responsive in $((SECONDS - start))s"
  exit 0
fi

echo "::error::sim-boot: $udid did not finish booting within ${budget}s (elapsed $((SECONDS - start))s, bootstatus status $booted)"
xcrun simctl list devices | grep -F "$udid" || echo "sim-boot: $udid is not listed by simctl"
exit 1
