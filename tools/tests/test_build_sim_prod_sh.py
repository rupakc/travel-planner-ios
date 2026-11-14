"""scripts/ci/build-sim-prod.sh against a fake xcodebuild and ditto: Release, unsigned, prod settings."""
import os
import shutil
import stat
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def _run(tmp_path: Path, produce_app: bool):
    root = (tmp_path / "repo").resolve()
    (root / "scripts/ci").mkdir(parents=True)
    shutil.copy(REPO / "scripts/ci/build-sim-prod.sh", root / "scripts/ci/build-sim-prod.sh")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    app = root / "build/DerivedData-sim-prod/Build/Products/Release-iphonesimulator/Voyager.app"
    make = f'mkdir -p "{app}"\n' if produce_app else ""
    (bin_dir / "xcodebuild").write_text(f'#!/bin/bash\nprintf "%s\\n" "$@" > "{root}/args"\n{make}')
    (bin_dir / "ditto").write_text('#!/bin/bash\nfor last; do :; done\ntouch "$last"\n')
    for p in (bin_dir / "xcodebuild", bin_dir / "ditto", root / "scripts/ci/build-sim-prod.sh"):
        p.chmod(p.stat().st_mode | stat.S_IXUSR)
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}"}
    result = subprocess.run([str(root / "scripts/ci/build-sim-prod.sh")], env=env, capture_output=True, text=True, timeout=30)
    return result, root


def test_release_unsigned_prod_settings(tmp_path):
    result, root = _run(tmp_path, True)
    assert result.returncode == 0, result.stderr
    args = (root / "args").read_text().splitlines()
    assert args[args.index("-configuration") + 1] == "Release"
    assert args[args.index("-sdk") + 1] == "iphonesimulator"
    assert "CODE_SIGNING_ALLOWED=NO" in args
    assert "VOYAGER_PROD_BASE_URL=https://35-207-18-35.sslip.io" in args
    assert "VOYAGER_TRUSTED_HOSTS=35-207-18-35.sslip.io" in args
    assert (root / "build/Voyager-sim-prod.zip").exists()


def test_missing_app_fails(tmp_path):
    result, _ = _run(tmp_path, False)
    assert result.returncode != 0
    assert "was not produced" in result.stderr
