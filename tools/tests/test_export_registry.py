"""Tests for tools/export_registry.py (runs on the vendored Upstream/registry.py)."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "export_registry.py"
REGISTRY = ROOT / "Upstream" / "registry.py"
EXPORTED = ROOT / "Upstream" / "telemetry_registry.json"
TEST_COPY = ROOT / "Packages/VoyagerKit/Tests/TelemetryTests/Resources/telemetry_registry.json"


def _export(tmp_path, registry=REGISTRY):
    out = tmp_path / "out.json"
    subprocess.run([sys.executable, str(TOOL), str(registry), str(out)], check=True)
    return out


def test_exports_events_and_platforms(tmp_path):
    data = json.loads(_export(tmp_path).read_text())
    assert data["events"]["screen_view"] == {"route": "id", "referrer_route": "id"}
    assert "ios" in data["platforms"]
    assert data["platforms"] == sorted(data["platforms"])
    assert set(data) == {"events", "platforms"}


def test_output_has_sorted_keys_and_trailing_newline(tmp_path):
    text = _export(tmp_path).read_text()
    assert text.endswith("}\n")
    assert text == json.dumps(json.loads(text), indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def test_committed_exports_match_vendored_registry(tmp_path):
    text = _export(tmp_path).read_text()
    assert EXPORTED.read_text() == text
    assert TEST_COPY.read_text() == text


def test_registry_is_loaded_without_backend_imports(tmp_path):
    fake = tmp_path / "registry.py"
    fake.write_text(
        'EVENTS = {"b": {"z": "id"}, "a": {}}\n_PLATFORMS = {"web", "ios"}\n'
    )
    data = json.loads(_export(tmp_path, fake).read_text())
    assert list(data["events"]) == ["a", "b"]
    assert data["platforms"] == ["ios", "web"]


def test_missing_attribute_fails(tmp_path):
    fake = tmp_path / "registry.py"
    fake.write_text("EVENTS = {}\n")
    result = subprocess.run(
        [sys.executable, str(TOOL), str(fake), str(tmp_path / "o.json")],
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert "_PLATFORMS" in result.stderr
