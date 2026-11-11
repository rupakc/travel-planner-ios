"""Tests for tools/gen_tokens.py (runs on the vendored Upstream/tokens.json)."""

import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "gen_tokens.py"
TOKENS = ROOT / "Upstream" / "tokens.json"
DS = Path("Packages/VoyagerKit/Sources/DesignSystem")

spec = importlib.util.spec_from_file_location("gen_tokens", TOOL)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def _run(root, *args):
    return subprocess.run(
        [sys.executable, str(TOOL), "--root", str(root), *args],
        capture_output=True,
        text=True,
    )


def _sandbox(tmp_path):
    (tmp_path / "Upstream").mkdir()
    shutil.copy(TOKENS, tmp_path / "Upstream" / "tokens.json")
    return tmp_path


def test_every_family_and_stop_has_light_and_dark(tmp_path):
    root = _sandbox(tmp_path)
    assert _run(root).returncode == 0
    catalog = root / DS / "Resources" / "Colors.xcassets"
    sets = sorted(p.name for p in catalog.glob("*.colorset"))
    tokens = json.loads(TOKENS.read_text())
    families = [f for f in tokens["palette"] if f != "white"]
    assert len(families) == 22
    assert len(sets) == 22 * 11 + 1
    for family in families:
        for stop in tokens["palette"][family]:
            assert f"{family}-{stop}.colorset" in sets
    assert "white.colorset" in sets
    for name in sets:
        contents = json.loads((catalog / name / "Contents.json").read_text())
        colors = contents["colors"]
        assert len(colors) == 2
        assert "appearances" not in colors[0]
        assert colors[1]["appearances"] == [{"appearance": "luminosity", "value": "dark"}]
        for entry in colors:
            assert entry["color"]["color-space"] == "srgb"
    palette_swift = (root / DS / "Generated" / "Palette.swift").read_text()
    assert "case teal" in palette_swift and "case s950 = 950" in palette_swift
    teal = json.loads((catalog / "teal-600.colorset" / "Contents.json").read_text())
    assert teal["colors"][0]["color"]["components"]["green"] == "0.580"
    # dark appearance comes from the `dark` map (teal-600 dark = #3ac7b6)
    assert teal["colors"][1]["color"]["components"]["red"] == "0.227"


def test_hex_to_components():
    c = gen.hex_to_components("#0d9488")
    assert c == {"red": "0.051", "green": "0.580", "blue": "0.533", "alpha": "1.000"}


def test_check_detects_drift(tmp_path):
    root = _sandbox(tmp_path)
    assert _run(root).returncode == 0
    assert _run(root, "--check").returncode == 0
    victim = root / DS / "Resources" / "Colors.xcassets" / "teal-600.colorset" / "Contents.json"
    victim.write_text(victim.read_text().replace("0.580", "0.581"))
    assert _run(root, "--check").returncode == 1
    assert _run(root).returncode == 0
    (root / DS / "Generated" / "Palette.swift").write_text("// edited\n")
    assert _run(root, "--check").returncode == 1


def test_check_detects_stray_colorset(tmp_path):
    root = _sandbox(tmp_path)
    assert _run(root).returncode == 0
    stray = root / DS / "Resources" / "Colors.xcassets" / "bogus-1.colorset"
    stray.mkdir()
    (stray / "Contents.json").write_text("{}")
    assert _run(root, "--check").returncode == 1


def test_committed_outputs_are_current():
    assert _run(ROOT, "--check").returncode == 0
