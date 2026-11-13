#!/usr/bin/env bash
# Create (once per job) the pinned simulator and print its xcodebuild destination:
#
#   scripts/ci/sim-destination.sh iphone|ipad   ->  platform=iOS Simulator,id=<udid>
#
# PINNED (snapshots are recorded and compared on exactly this; never "newest available"):
#   iphone: device type "iPhone 16"              on com.apple.CoreSimulator.SimRuntime.iOS-18-6 (iOS 18.6)
#   ipad:   device type "iPad Pro 13-inch (M4)"  on com.apple.CoreSimulator.SimRuntime.iOS-18-6 (iOS 18.6)
# Built with the pinned Xcode 26.0.1 / iOS 26 SDK (XCODE_VERSION in ios-ci.yml); the app's deployment target is
# iOS 17, so iOS 18.6 is a valid test runtime. It is preinstalled on GitHub's macos-15 arm64 image and boots
# reliably there; the image's iOS 26.0 simulators took 100-330 s to boot and often wedged (2026-11-12).
#
# Each job gets its own fresh device, `voyager-ci-<family>`, created here with `simctl create` (or reused when this
# job already created it); the image's stock devices are never booted, reset or deleted. If the image lacks the
# pinned runtime or device type, or the new device is not listed as available, this FAILS (no fallback): a silent
# fallback renders every snapshot differently.
#
# To bump (new runtime or device):
#   1. change SIM_RUNTIME / SIM_IPHONE / SIM_IPAD below (and XCODE_VERSION in ios-ci.yml if the SDK changes);
#   2. on the bump PR, re-record every snapshot on the new pin:
#        gh workflow run ios-ci.yml --ref <branch> -f record_snapshots=true
#        gh run download <id> -n snapshots -D Packages/VoyagerKit/Tests
#      commit the PNGs, and check the next PR run is green against them.
set -euo pipefail

SIM_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-18-6"
SIM_IPHONE="iPhone 16"
SIM_IPAD="iPad Pro 13-inch (M4)"

family="${1:-}"
case "$family" in
  iphone) type_name="$SIM_IPHONE" ;;
  ipad) type_name="$SIM_IPAD" ;;
  *) echo "usage: $0 iphone|ipad" >&2; exit 2 ;;
esac
name="voyager-ci-$family"

# find_device: the udid of an available `voyager-ci-<family>` on the pinned runtime, or nothing.
find_device() {
  xcrun simctl list devices -j | python3 -c '
import json, sys
runtime, name = sys.argv[1], sys.argv[2]
for d in json.load(sys.stdin)["devices"].get(runtime, []):
    if d["name"] == name and d.get("isAvailable", False):
        print(d["udid"]); break' "$SIM_RUNTIME" "$name"
}

# Check the pin exists on this image: the runtime (available) and the device type it supports.
RUNTIMES_JSON="$(xcrun simctl list runtimes -j)" python3 - "$SIM_RUNTIME" "$type_name" <<'PY2'
import json, os, sys

runtime_id, type_name = sys.argv[1], sys.argv[2]
runtimes = {r["identifier"]: r for r in json.loads(os.environ["RUNTIMES_JSON"])["runtimes"]}
runtime = runtimes.get(runtime_id)


def fail(msg):
    print("::error::sim-destination: " + msg, file=sys.stderr)
    ios = sorted("%s (%s, available=%s)" % (i, r.get("version"), r.get("isAvailable"))
                 for i, r in runtimes.items() if ".iOS-" in i)
    print("sim-destination: iOS runtimes on this runner:\n  " + "\n  ".join(ios), file=sys.stderr)
    print("sim-destination: see the bump steps at the top of scripts/ci/sim-destination.sh", file=sys.stderr)
    sys.exit(1)


if runtime is None or not runtime.get("isAvailable", False):
    fail("pinned runtime %s is missing or unavailable (%s)" % (runtime_id, runtime and runtime.get("availabilityError")))
types = [t.get("name") for t in runtime.get("supportedDeviceTypes", [])]
if types and type_name not in types:
    fail('pinned runtime %s does not support device type "%s"; it supports: %s' % (runtime_id, type_name, ", ".join(types)))
PY2

udid="$(find_device)"
if [[ -z "$udid" ]]; then
  if ! udid="$(xcrun simctl create "$name" "$type_name" "$SIM_RUNTIME" 2>&1)"; then
    echo "::error::sim-destination: simctl create \"$name\" \"$type_name\" $SIM_RUNTIME failed: $udid" >&2
    exit 1
  fi
  # Use the device only once CoreSimulator lists it as available (xcodebuild resolves the id from that list).
  for _ in $(seq 1 30); do
    [[ "$(find_device)" == "$udid" ]] && break
    sleep 1
  done
  if [[ "$(find_device)" != "$udid" ]]; then
    echo "::error::sim-destination: created $udid but it is not listed as an available device on $SIM_RUNTIME" >&2
    exit 1
  fi
  echo "sim-destination: created $name ($type_name) on $SIM_RUNTIME udid=$udid" >&2
else
  echo "sim-destination: reusing $name ($type_name) on $SIM_RUNTIME udid=$udid" >&2
fi
echo "platform=iOS Simulator,id=$udid"
