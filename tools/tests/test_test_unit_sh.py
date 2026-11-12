"""scripts/ci/test-unit.sh against a fake xcodebuild: pass, hang (watchdog), project-source warning."""
import os
import shutil
import stat
import subprocess
import textwrap
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]


def _run(tmp_path: Path, fake_body: str, unit_timeout: str = "60"):
    root = (tmp_path / "repo").resolve()
    (root / "scripts/ci").mkdir(parents=True)
    (root / "Packages/VoyagerKit").mkdir(parents=True)
    shutil.copy(REPO / "scripts/ci/test-unit.sh", root / "scripts/ci/test-unit.sh")
    destination = root / "scripts/ci/sim-destination.sh"
    destination.write_text('#!/bin/sh\necho "platform=iOS Simulator,id=FAKE"\n')
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake = bin_dir / "xcodebuild"
    fake.write_text("#!/bin/bash\n" + textwrap.dedent(fake_body).replace("@ROOT@", str(root)))
    for path in (fake, destination, root / "scripts/ci/test-unit.sh"):
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "UNIT_TIMEOUT": unit_timeout}
    result = subprocess.run(
        [str(root / "scripts/ci/test-unit.sh"), "iphone"], env=env, capture_output=True, text=True, timeout=90
    )
    return result, root


def test_passing_run_exits_zero_and_keeps_the_log(tmp_path):
    result, root = _run(tmp_path, 'echo "Test run passed"\n')
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Test run passed" in (root / "build/unit-iphone.log").read_text()


def test_hung_run_is_stopped_with_124(tmp_path):
    result, root = _run(tmp_path, 'echo started\nsleep 300\n', unit_timeout="2")
    assert result.returncode == 124, result.stdout + result.stderr
    assert "exceeded 2s" in result.stdout
    assert "started" in (root / "build/unit-iphone.log").read_text()


def test_warning_in_project_sources_fails_after_the_log_is_complete(tmp_path):
    body = """
    for i in $(seq 1 200); do echo "noise $i"; done
    echo "@ROOT@/Packages/VoyagerKit/Sources/Domain/X.swift:3:4: warning: unused variable"
    """
    result, _ = _run(tmp_path, body)
    assert result.returncode == 1, result.stdout + result.stderr
    assert "Compiler warnings in project sources" in result.stdout


def test_warning_outside_project_sources_is_ignored(tmp_path):
    result, _ = _run(tmp_path, 'echo "/elsewhere/Pkg/Sources/Y.swift:1:1: warning: not ours"\n')
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.skipif(shutil.which("pkill") is None, reason="needs pkill")
def test_no_orphaned_watchdog_sleep_after_a_passing_run(tmp_path):
    result, _ = _run(tmp_path, "true\n", unit_timeout="777")
    assert result.returncode == 0
    leftover = subprocess.run(["pgrep", "-f", "sleep 777"], capture_output=True, text=True)
    assert leftover.stdout.strip() == ""
