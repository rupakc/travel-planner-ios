"""scripts/ci/sim-destination.sh against a stateful fake xcrun: creates one fresh device per job on the pinned
runtime, reuses it within the job, never touches stock devices, and fails loudly when the pin is missing."""
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PIN = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"
TYPES = [{"name": "iPhone 16"}, {"name": "iPad Pro 13-inch (M4)"}]
RUNTIMES = [
    {"identifier": PIN, "version": "18.6", "isAvailable": True, "supportedDeviceTypes": TYPES},
    {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0", "version": "26.0.1", "isAvailable": True},
]
STOCK = {PIN: [{"name": "iPhone 16", "udid": "STOCK", "isAvailable": True, "state": "Shutdown"}]}

# Fake xcrun: `simctl list runtimes|devices -j` print the JSON state; `simctl create` appends a device (or fails
# when create.fail exists) and prints its udid.
FAKE = r'''#!/bin/bash
dir="$(dirname "$0")"
echo "$*" >> "$dir/calls"
if [[ "$2" == list && "$3" == runtimes ]]; then cat "$dir/runtimes.json"; exit; fi
if [[ "$2" == list && "$3" == devices ]]; then cat "$dir/devices.json"; exit; fi
if [[ "$2" == create ]]; then
  [[ -e "$dir/create.fail" ]] && { echo "Invalid device type: $4" >&2; exit 1; }
  udid="NEW-$(wc -l < "$dir/calls" | tr -d ' ')"
  python3 - "$dir/devices.json" "$3" "$5" "$udid" <<'PY'
import json, sys
path, name, runtime, udid = sys.argv[1:]
d = json.load(open(path))
d["devices"].setdefault(runtime, []).append({"name": name, "udid": udid, "isAvailable": True, "state": "Shutdown"})
json.dump(d, open(path, "w"))
PY
  echo "$udid"; exit
fi
exit 1
'''


def _setup(tmp_path: Path, runtimes=RUNTIMES, devices=STOCK, create_fails=False) -> Path:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "runtimes.json").write_text(json.dumps({"runtimes": runtimes}))
    (bin_dir / "devices.json").write_text(json.dumps({"devices": devices}))
    if create_fails:
        (bin_dir / "create.fail").write_text("")
    xcrun = bin_dir / "xcrun"
    xcrun.write_text(FAKE)
    xcrun.chmod(xcrun.stat().st_mode | stat.S_IXUSR)
    shutil.copy(REPO / "scripts/ci/sim-destination.sh", tmp_path / "sim-destination.sh")
    return bin_dir


def _run(tmp_path: Path, bin_dir: Path, family: str):
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
    return subprocess.run(
        ["bash", str(tmp_path / "sim-destination.sh"), family], env=env, capture_output=True, text=True, timeout=60
    )


def test_creates_a_fresh_pinned_iphone_and_ignores_stock_devices(tmp_path):
    bin_dir = _setup(tmp_path)
    result = _run(tmp_path, bin_dir, "iphone")
    assert result.returncode == 0, result.stderr
    udid = result.stdout.strip().removeprefix("platform=iOS Simulator,id=")
    assert udid.startswith("NEW-")
    assert f"simctl create voyager-ci-iphone iPhone 16 {PIN}" in (bin_dir / "calls").read_text()
    assert "STOCK" not in result.stdout


def test_reuses_the_device_it_created_in_the_same_job(tmp_path):
    bin_dir = _setup(tmp_path)
    first = _run(tmp_path, bin_dir, "ipad").stdout
    second = _run(tmp_path, bin_dir, "ipad")
    assert second.returncode == 0, second.stderr
    assert second.stdout == first
    assert (bin_dir / "calls").read_text().count("simctl create") == 1
    assert "reusing voyager-ci-ipad (iPad Pro 13-inch (M4))" in second.stderr


def test_missing_runtime_fails_loudly(tmp_path):
    bin_dir = _setup(tmp_path, runtimes=RUNTIMES[1:])
    result = _run(tmp_path, bin_dir, "iphone")
    assert result.returncode == 1 and result.stdout == ""
    assert f"::error::sim-destination: pinned runtime {PIN} is missing" in result.stderr
    assert "iOS-26-0" in result.stderr


def test_unsupported_device_type_fails_loudly(tmp_path):
    runtimes = [{**RUNTIMES[0], "supportedDeviceTypes": [{"name": "iPhone 16"}]}]
    bin_dir = _setup(tmp_path, runtimes=runtimes)
    result = _run(tmp_path, bin_dir, "ipad")
    assert result.returncode == 1 and result.stdout == ""
    assert 'does not support device type "iPad Pro 13-inch (M4)"' in result.stderr


def test_create_failure_fails_loudly_with_the_simctl_error(tmp_path):
    bin_dir = _setup(tmp_path, create_fails=True)
    result = _run(tmp_path, bin_dir, "iphone")
    assert result.returncode == 1 and result.stdout == ""
    assert "simctl create" in result.stderr and "Invalid device type" in result.stderr
