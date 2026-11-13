"""scripts/ci/sim-boot.sh and scripts/ci/test-ui.sh against fake xcrun / xcodebuild / sim-* scripts."""
import os
import shutil
import stat
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def _exe(path: Path, body: str) -> None:
    path.write_text("#!/bin/bash\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _boot(tmp_path: Path, bootstatus: str, state: str = "Booting", attempt_timeout: str = "5", attempts: str = "2"):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "calls"
    _exe(bin_dir / "xcrun", f"""
echo "$2" >> "{calls}"
case "$2" in
  boot) exit 0 ;;
  bootstatus) n=$(grep -c '^bootstatus$' "{calls}"); {bootstatus} ;;
  spawn) exit 0 ;;
  list) echo "    iPhone 16 (UDID) ({state})" ;;
esac
""")
    env = {
        **os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "SIM_POLL_SECONDS": "1",
        "SIM_BOOT_ATTEMPT_TIMEOUT": attempt_timeout, "SIM_BOOT_ATTEMPTS": attempts,
    }
    result = subprocess.run(
        ["bash", str(REPO / "scripts/ci/sim-boot.sh"), "UDID"], env=env, capture_output=True, text=True, timeout=60
    )
    return result, calls.read_text().split()


def test_healthy_boot_is_ready_when_bootstatus_returns(tmp_path):
    result, calls = _boot(tmp_path, "echo booted")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "UDID booted in" in result.stdout and "attempt 1" in result.stdout
    assert "erase" not in calls and "boot" not in calls and "spawn" not in calls


def test_booted_is_not_ready_until_bootstatus_returns(tmp_path):
    # CI showed Booted + launchd answering while bootstatus waited, and UIKit tests hung on that device.
    result, calls = _boot(tmp_path, "exec sleep 120", state="Booted", attempt_timeout="3")
    assert result.returncode == 1
    assert "state Booted, bootstatus still waiting" in result.stdout
    assert calls.count("erase") == 1


def test_hung_boot_is_erased_and_booted_again(tmp_path):
    result, calls = _boot(tmp_path, "[[ $n -eq 1 ]] && exec sleep 120; echo booted", attempt_timeout="3")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "attempt 1: UDID not booted within 3s" in result.stdout and "state Booting" in result.stdout
    assert "attempt 2" in result.stdout
    assert calls.count("erase") == 1 and "delete" not in calls and "create" not in calls


def test_boot_that_never_gets_ready_fails_loudly(tmp_path):
    result, calls = _boot(tmp_path, "exec sleep 120", attempt_timeout="3")
    assert result.returncode == 1
    assert "::error::sim-boot: UDID did not boot in 2 attempt(s) of 3s" in result.stdout
    assert calls.count("bootstatus") == 2 and calls.count("erase") == 1


def test_no_bootstatus_left_running(tmp_path):
    _boot(tmp_path, "exec sleep 97", attempt_timeout="2", attempts="1")
    leftover = subprocess.run(["pgrep", "-f", "sleep 97"], capture_output=True, text=True)
    assert leftover.stdout.strip() == ""


def _ui(tmp_path: Path, failing_boot: str):
    root = (tmp_path / "repo").resolve()
    (root / "scripts/ci").mkdir(parents=True)
    shutil.copy(REPO / "scripts/ci/test-ui.sh", root / "scripts/ci/test-ui.sh")
    _exe(root / "scripts/ci/sim-destination.sh", 'echo "platform=iOS Simulator,id=ID-$1"\n')
    _exe(root / "scripts/ci/sim-boot.sh", f"""
echo "start $1 $(date +%s%N)" >> "{root}/calls"; sleep 1; echo "end $1 $(date +%s%N)" >> "{root}/calls"
[[ "$1" == "ID-{failing_boot}" ]] && exit 1 || exit 0
""")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _exe(bin_dir / "xcodebuild", f'echo "xcodebuild $1 $*" >> "{root}/calls"\n')
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
    result = subprocess.run(
        ["bash", str(root / "scripts/ci/test-ui.sh"), "iphone", "ipad"],
        env=env, capture_output=True, text=True, timeout=60,
    )
    return result, (root / "calls").read_text().splitlines()


def test_ui_boots_one_simulator_at_a_time_and_tests_both(tmp_path):
    result, calls = _ui(tmp_path, failing_boot="none")
    assert result.returncode == 0, result.stdout + result.stderr
    boots = [c.split()[:2] for c in calls if c.startswith(("start", "end"))]
    assert boots == [["start", "ID-iphone"], ["end", "ID-iphone"], ["start", "ID-ipad"], ["end", "ID-ipad"]]
    tests = [c for c in calls if c.startswith("xcodebuild test-without-building")]
    assert [("ID-iphone" in t, "ID-ipad" in t) for t in tests] == [(True, False), (False, True)]


def test_ui_a_failed_boot_skips_that_device_runs_the_other_and_fails(tmp_path):
    result, calls = _ui(tmp_path, failing_boot="iphone")
    assert result.returncode == 1
    assert "iphone simulator did not boot" in result.stdout
    tests = [c for c in calls if c.startswith("xcodebuild test-without-building")]
    assert len(tests) == 1 and "ID-ipad" in tests[0]


def test_no_orphaned_poller_sleep_after_a_boot(tmp_path):
    result, _ = _boot(tmp_path, "echo booted")
    assert result.returncode == 0, result.stdout + result.stderr
    leftover = subprocess.run(["pgrep", "-f", "^sleep 30$"], capture_output=True, text=True)
    assert leftover.stdout.strip() == ""
