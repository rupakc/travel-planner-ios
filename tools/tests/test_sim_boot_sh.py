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


def _boot(tmp_path: Path, bootstatus: str, budget: str = "5"):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _exe(bin_dir / "xcrun", f"""
case "$2" in
  boot) exit 0 ;;
  bootstatus) {bootstatus} ;;
  spawn) exit 0 ;;
  list) echo "    iPhone 16 (UDID) (Booted)" ;;
esac
""")
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "SIM_BOOT_TIMEOUT": budget}
    return subprocess.run(
        ["bash", str(REPO / "scripts/ci/sim-boot.sh"), "UDID"], env=env, capture_output=True, text=True, timeout=60
    )


def test_boot_logs_each_stage_once_and_succeeds(tmp_path):
    result = _boot(tmp_path, 'echo "Waiting on System App"; echo "Waiting on System App"; echo "Device booted"')
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count("Waiting on System App") == 1
    assert "booted and responsive" in result.stdout


def test_stalled_boot_fails_loudly_within_the_budget(tmp_path):
    result = _boot(tmp_path, 'echo "Waiting on Data Migration"; exec sleep 120', budget="3")
    assert result.returncode == 1
    assert "Waiting on Data Migration" in result.stdout
    assert "::error::sim-boot: UDID did not finish booting within 3s" in result.stdout


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
