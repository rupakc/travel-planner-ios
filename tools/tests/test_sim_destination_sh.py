"""scripts/ci/sim-destination.sh against a fake xcrun: picks the pinned device + runtime, fails loudly otherwise."""
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PIN = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"


def _device(name, udid, available=True):
    return {"name": name, "udid": udid, "isAvailable": available, "state": "Shutdown"}


def _run(tmp_path: Path, family: str, runtimes: list, devices: dict):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (tmp_path / "runtimes.json").write_text(json.dumps({"runtimes": runtimes}))
    (tmp_path / "devices.json").write_text(json.dumps({"devices": devices}))
    xcrun = bin_dir / "xcrun"
    xcrun.write_text(f'#!/bin/bash\n[[ "$3" == runtimes ]] && cat "{tmp_path}/runtimes.json" || cat "{tmp_path}/devices.json"\n')
    xcrun.chmod(xcrun.stat().st_mode | stat.S_IXUSR)
    script = tmp_path / "sim-destination.sh"
    shutil.copy(REPO / "scripts/ci/sim-destination.sh", script)
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
    return subprocess.run(["bash", str(script), family], env=env, capture_output=True, text=True, timeout=30)


RUNTIMES = [
    {"identifier": PIN, "version": "26.0.1", "isAvailable": True},
    {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2", "version": "26.2", "isAvailable": True},
]


def test_pinned_iphone_on_the_pinned_runtime_not_the_newest_lowest_udid(tmp_path):
    devices = {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [_device("iPhone 16", "AAAA")],
        PIN: [_device("iPhone 16 Pro", "BBBB"), _device("iPhone 16", "DDDD"), _device("iPhone 16", "CCCC")],
    }
    result = _run(tmp_path, "iphone", RUNTIMES, devices)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "platform=iOS Simulator,id=CCCC"
    assert "iPhone 16 on " + PIN in result.stderr


def test_pinned_ipad(tmp_path):
    devices = {PIN: [_device("iPad Air 11-inch (M2)", "AAAA"), _device("iPad Pro 13-inch (M4)", "EEEE")]}
    result = _run(tmp_path, "ipad", RUNTIMES, devices)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "platform=iOS Simulator,id=EEEE"


def test_missing_device_fails_loudly(tmp_path):
    devices = {PIN: [_device("iPhone 16 Pro", "BBBB"), _device("iPhone 16", "CCCC", available=False)]}
    result = _run(tmp_path, "iphone", RUNTIMES, devices)
    assert result.returncode == 1
    assert result.stdout == ""
    assert '::error::sim-destination: pinned device "iPhone 16" not found' in result.stderr


def test_missing_runtime_fails_loudly(tmp_path):
    devices = {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [_device("iPhone 16", "AAAA")]}
    result = _run(tmp_path, "iphone", RUNTIMES[1:], devices)
    assert result.returncode == 1
    assert "pinned runtime " + PIN + " is missing" in result.stderr
    assert "iOS-26-2" in result.stderr
