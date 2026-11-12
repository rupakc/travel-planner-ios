#!/usr/bin/env bash
# Print the xcodebuild destination of the pinned simulator:
#
#   scripts/ci/sim-destination.sh iphone|ipad   ->  platform=iOS Simulator,id=<udid>
#
# PINNED (snapshots are recorded and compared on exactly this; never "newest available"):
#   iphone: "iPhone 16"              on com.apple.CoreSimulator.SimRuntime.iOS-26-0 (iOS 26.0.1)
#   ipad:   "iPad Pro 13-inch (M4)"  on com.apple.CoreSimulator.SimRuntime.iOS-26-0 (iOS 26.0.1)
# iOS 26.0 is the runtime of the pinned Xcode 26.0.1 SDK (XCODE_VERSION in ios-ci.yml) and is preinstalled on
# GitHub's macos-15 arm64 image (which also carries 18.5, 18.6, 26.1, 26.2). If the image ever lacks the pinned
# device or runtime this script FAILS (no fallback): a silent fallback renders every snapshot differently.
#
# To bump (new Xcode, or the image drops iOS 26.0):
#   1. change SIM_RUNTIME (and the device names if needed) below and XCODE_VERSION in ios-ci.yml together;
#   2. on the bump PR, re-record every snapshot on the new pin:
#        gh workflow run ios-ci.yml --ref <branch> -f record_snapshots=true
#        gh run download <id> -n snapshots -D Packages/VoyagerKit/Tests
#      commit the PNGs, and check the next PR run is green against them.
# When several devices share the pinned name and runtime, the lowest UDID wins (deterministic per image).
set -euo pipefail

SIM_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-0"
SIM_IPHONE="iPhone 16"
SIM_IPAD="iPad Pro 13-inch (M4)"

family="${1:-}"
case "$family" in
  iphone) name="$SIM_IPHONE" ;;
  ipad) name="$SIM_IPAD" ;;
  *) echo "usage: $0 iphone|ipad" >&2; exit 2 ;;
esac

runtimes_json="$(xcrun simctl list runtimes -j)"
devices_json="$(xcrun simctl list devices -j)"

RUNTIMES_JSON="$runtimes_json" DEVICES_JSON="$devices_json" python3 - "$SIM_RUNTIME" "$name" <<'PY'
import json, os, sys

runtime_id, name = sys.argv[1], sys.argv[2]
runtimes = {r["identifier"]: r for r in json.loads(os.environ["RUNTIMES_JSON"])["runtimes"]}
devices = json.loads(os.environ["DEVICES_JSON"])["devices"]

def fail(msg):
    print(f"::error::sim-destination: {msg}", file=sys.stderr)
    ios = sorted(f"{r['identifier']} ({r.get('version')}, available={r.get('isAvailable')})"
                 for r in runtimes.values() if ".iOS-" in r["identifier"])
    print("sim-destination: iOS runtimes on this runner:\n  " + "\n  ".join(ios), file=sys.stderr)
    print("sim-destination: see the bump steps at the top of scripts/ci/sim-destination.sh", file=sys.stderr)
    sys.exit(1)

runtime = runtimes.get(runtime_id)
if runtime is None or not runtime.get("isAvailable", False):
    fail(f"pinned runtime {runtime_id} is missing or unavailable ({runtime and runtime.get('availabilityError')})")
matches = sorted(
    (d for d in devices.get(runtime_id, []) if d["name"] == name and d.get("isAvailable", False)),
    key=lambda d: d["udid"],
)
if not matches:
    names = sorted({d["name"] for d in devices.get(runtime_id, [])})
    fail(f'pinned device "{name}" not found on {runtime_id}; devices there: {", ".join(names) or "none"}')
pick = matches[0]
print(f"sim-destination: {pick['name']} on {runtime_id} (iOS {runtime.get('version')}) "
      f"udid={pick['udid']} state={pick.get('state')}", file=sys.stderr)
print(f"platform=iOS Simulator,id={pick['udid']}")
PY
