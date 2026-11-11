#!/usr/bin/env bash
# Print an xcodebuild destination for an available simulator:
#
#   scripts/ci/sim-destination.sh iphone|ipad   ->  platform=iOS Simulator,id=<udid>
#
# Uses the newest iOS runtime the selected Xcode's SDK supports, preferring
# iPhone 16 / iPhone 16 Pro (any iPhone otherwise), or iPad Pro 13-inch (M4) /
# iPad Air 11-inch (M2) (any iPad otherwise).
set -euo pipefail

family="${1:-}"
case "$family" in
  iphone) preferred='["iPhone 16", "iPhone 16 Pro"]'; prefix="iPhone" ;;
  ipad) preferred='["iPad Pro 13-inch (M4)", "iPad Air 11-inch (M2)"]'; prefix="iPad" ;;
  *) echo "usage: $0 iphone|ipad" >&2; exit 2 ;;
esac

sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
devices_json="$(xcrun simctl list devices available -j)"

DEVICES_JSON="$devices_json" python3 - "$prefix" "$preferred" "$sdk_version" <<'PY'
import json, os, re, sys

prefix, preferred, sdk = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3]
devices = json.loads(os.environ["DEVICES_JSON"])["devices"]

def version(runtime):
    m = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else None

sdk_v = tuple(int(x) for x in sdk.split(".")[:2])
runtimes = sorted(
    ((v, r) for r in devices if (v := version(r)) is not None and v <= sdk_v),
    reverse=True,
)
for _, runtime in runtimes:
    available = [d for d in devices[runtime] if d.get("isAvailable", True) and d["name"].startswith(prefix)]
    if not available:
        continue
    by_name = {d["name"]: d for d in available}
    pick = next((by_name[n] for n in preferred if n in by_name), available[0])
    print(f"sim-destination: {pick['name']} on {runtime}", file=sys.stderr)
    print(f"platform=iOS Simulator,id={pick['udid']}")
    sys.exit(0)

print(f"sim-destination: no available {prefix} simulator for iOS <= {sdk}", file=sys.stderr)
sys.exit(1)
PY
