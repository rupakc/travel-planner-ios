"""Tests for tools/gen_catalog.py: real data checks plus small synthetic trees."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import gen_catalog  # noqa: E402

ROOT = TOOLS.parent
SCRIPT = TOOLS / "gen_catalog.py"


def _real():
    result = gen_catalog.build(ROOT)
    return result, gen_catalog.localizable(result)["strings"]


def _loc(strings, key, lang):
    return strings[key]["localizations"][lang]


def _write(root: Path, lang: str, ns: str, tree: dict, pending=False):
    base = root / "i18n/pending" / lang if pending else root / "Upstream/locales" / lang
    base.mkdir(parents=True, exist_ok=True)
    (base / f"{ns}.json").write_text(json.dumps(tree, ensure_ascii=False), encoding="utf-8")


def _tree(tmp_path, en: dict, **others):
    """A tiny repo: namespace `t`, English plus other languages (default: copies of English)."""
    _write(tmp_path, "en", "t", en)
    for lang in gen_catalog.LANGUAGES:
        if lang != "en":
            _write(tmp_path, lang, "t", others.get(lang, en))
    return tmp_path


def _run(root, *args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(root), *args], capture_output=True, text=True
    )


def test_plain_key_flattened():
    _, strings = _real()
    assert _loc(strings, "common:nav.search", "en")["stringUnit"] == {"state": "translated", "value": "Search"}
    assert _loc(strings, "common:nav.search", "de")["stringUnit"]["value"] == "Suche"
    assert strings["common:nav.search"]["extractionState"] == "manual"
    assert set(strings["common:nav.search"]["localizations"]) == {"en", "es", "de", "fr", "hi", "zh-Hans", "bn"}


def test_plural_becomes_substitution():
    _, strings = _real()
    en = _loc(strings, "common:nav.unread", "en")
    assert en["stringUnit"]["value"] == "%#@count@"
    sub = en["substitutions"]["count"]
    assert sub["argNum"] == 1 and sub["formatSpecifier"] == "lld"
    forms = sub["variations"]["plural"]
    assert set(forms) == {"one", "other"}
    assert forms["one"]["stringUnit"]["value"] == "%arg unread"
    assert forms["other"]["stringUnit"]["value"] == "%arg unread"
    assert "common:nav.unread_one" not in strings


def test_bn_plural_forms_kept():
    result, strings = _real()
    plural_keys = [k for k, e in result.catalog["en"].items() if e.plural]
    assert plural_keys
    for key in plural_keys:
        bn = result.catalog["bn"][key]
        assert bn.forms is not None and {"one", "other"} <= set(bn.forms)
        forms = _loc(strings, key, "bn")["substitutions"]["count"]["variations"]["plural"]
        assert {"one", "other"} <= set(forms)


def test_zh_maps_to_zh_Hans():
    _, strings = _real()
    locs = strings["common:nav.search"]["localizations"]
    assert "zh-Hans" in locs and "zh" not in locs
    assert locs["zh-Hans"]["stringUnit"]["value"] == "搜索"


def test_percent_escaped_only_in_plurals(tmp_path):
    root = _tree(tmp_path, {"disc": "Save 50% now", "n_one": "{{count}}% done", "n_other": "{{count}}% done, {{who}}"})
    strings = gen_catalog.localizable(gen_catalog.build(root))["strings"]
    assert _loc(strings, "t:disc", "en")["stringUnit"]["value"] == "Save 50% now"
    forms = _loc(strings, "t:n", "en")["substitutions"]["count"]["variations"]["plural"]
    assert forms["one"]["stringUnit"]["value"] == "%arg%% done"
    assert forms["other"]["stringUnit"]["value"] == "%arg%% done, {{who}}"


def test_plural_form_may_omit_arg(tmp_path):
    root = _tree(tmp_path, {"n_one": "One item", "n_other": "{{count}} items"})
    strings = gen_catalog.localizable(gen_catalog.build(root))["strings"]
    forms = _loc(strings, "t:n", "en")["substitutions"]["count"]["variations"]["plural"]
    assert forms["one"]["stringUnit"]["value"] == "One item"


def test_missing_key_falls_back_to_english(tmp_path):
    en = {"a": "Alpha", "b": "Beta"}
    root = _tree(tmp_path, en, de={"a": "Alfa"})
    proc = _run(root)
    assert proc.returncode == 0, proc.stderr
    assert "missing: de t:b" in proc.stderr
    strings = json.loads((root / gen_catalog.LOCALIZABLE).read_text(encoding="utf-8"))["strings"]
    assert _loc(strings, "t:b", "de")["stringUnit"]["value"] == "Beta"
    assert _loc(strings, "t:a", "de")["stringUnit"]["value"] == "Alfa"


def test_pending_keys_get_english_everywhere(tmp_path):
    root = _tree(tmp_path, {"a": "Alpha"})
    _write(root, "en", "t", {"newKey": "Brand new"}, pending=True)
    proc = _run(root)
    assert proc.returncode == 0, proc.stderr
    assert "pending: 1 keys" in proc.stderr
    strings = json.loads((root / gen_catalog.LOCALIZABLE).read_text(encoding="utf-8"))["strings"]
    for code in gen_catalog.LANGUAGES.values():
        assert _loc(strings, "t:newKey", code)["stringUnit"]["value"] == "Brand new"
    assert "missing: de t:newKey" not in proc.stderr


def test_pending_collision_fails(tmp_path):
    root = _tree(tmp_path, {"a": "Alpha"})
    _write(root, "en", "t", {"a": "Different"}, pending=True)
    proc = _run(root)
    assert proc.returncode != 0
    assert "t:a" in proc.stderr
    assert not (root / gen_catalog.LOCALIZABLE).exists()


def test_keys_swift_sanitises_identifiers(tmp_path):
    root = _tree(
        tmp_path,
        {"a": {"default": "D", "x-y": "XY", "self": "S"}, "x": {"2fa": "Two", "plain": "P"}, "n_one": "{{count}} one", "n_other": "{{count}} {{what}}", "p": "Hi {{name}}"},
    )
    swift = gen_catalog.keys_swift(gen_catalog.build(root))
    assert 'public static let `default` = LKey("t:a.default", placeholders: [], plural: false)' in swift
    assert 'public static let _2fa = LKey("t:x.2fa"' in swift
    assert "public static let x_y = LKey" in swift
    assert "public static let self_ = LKey" in swift
    assert 'public static let n = LKey("t:n", placeholders: ["what"], plural: true)' in swift
    assert 'public static let p = LKey("t:p", placeholders: ["name"], plural: false)' in swift
    assert "public enum t {" in swift and "public enum K {" in swift


def test_keys_swift_real_catalogue_shape():
    result, _ = _real()
    swift = gen_catalog.keys_swift(result)
    assert 'public static let search = LKey("common:nav.search", placeholders: [], plural: false)' in swift
    assert 'public static let unread = LKey("common:nav.unread", placeholders: [], plural: true)' in swift
    assert 'LKey("auth:comingSoon", placeholders: ["provider"], plural: false)' in swift


def test_identifier_collision_fails(tmp_path):
    root = _tree(tmp_path, {"a-b": "1", "a_b": "2"})
    proc = _run(root)
    assert proc.returncode != 0 and "collides" in proc.stderr


def test_info_plist_from_mobile_namespace():
    result, _ = _real()
    plist, found = gen_catalog.info_plist(result)
    assert found
    strings = plist["strings"]
    assert strings["CFBundleDisplayName"]["localizations"]["de"]["stringUnit"]["value"] == "Voyager"
    en = strings["NSLocationWhenInUseUsageDescription"]["localizations"]["en"]["stringUnit"]["value"]
    assert en == result.catalog["en"]["mobile:infoPlist.location"].value


def test_info_plist_fallback_without_mobile(tmp_path):
    root = _tree(tmp_path, {"a": "Alpha"})
    proc = _run(root)
    assert proc.returncode == 0, proc.stderr
    assert "notice:" in proc.stderr
    plist = json.loads((root / gen_catalog.INFO_PLIST).read_text(encoding="utf-8"))
    assert list(plist["strings"]) == ["CFBundleDisplayName"]


def test_check_detects_drift(tmp_path):
    root = _tree(tmp_path, {"a": "Alpha"})
    assert _run(root, "--check").returncode == 1  # nothing generated yet
    assert _run(root).returncode == 0
    assert _run(root, "--check").returncode == 0
    for rel in (gen_catalog.LOCALIZABLE, gen_catalog.KEYS_SWIFT, gen_catalog.INFO_PLIST):
        path = root / rel
        original = path.read_text(encoding="utf-8")
        path.write_text(original + " ", encoding="utf-8")
        assert _run(root, "--check").returncode == 1, rel
        path.write_text(original, encoding="utf-8")
    _write(root, "en", "t", {"a": "Changed"})
    assert _run(root, "--check").returncode == 1


def test_committed_outputs_are_current():
    proc = _run(ROOT, "--check")
    assert proc.returncode == 0, proc.stderr


def test_output_is_deterministic(tmp_path):
    root = tmp_path / "copy"
    shutil.copytree(ROOT / "Upstream", root / "Upstream")
    assert _run(root).returncode == 0
    for rel in (gen_catalog.LOCALIZABLE, gen_catalog.KEYS_SWIFT, gen_catalog.INFO_PLIST):
        assert (root / rel).read_text(encoding="utf-8") == (ROOT / rel).read_text(encoding="utf-8")
