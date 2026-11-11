#!/usr/bin/env python3
"""Generate the iOS String Catalogs and key constants from the web's i18next catalogue.

    tools/gen_catalog.py [--check] [--root DIR]

Reads   Upstream/locales/<lang>/<ns>.json   (i18next JSON v4, vendored by scripts/upstream/sync.sh)
        i18n/pending/en/<ns>.json           (English-only keys not yet upstream)
Writes  Packages/VoyagerKit/Sources/L10n/Resources/Localizable.xcstrings
        Packages/VoyagerKit/Sources/L10n/Generated/Keys.swift
        App/Resources/InfoPlist.xcstrings

``--check`` writes nothing and exits 1 when a committed output differs from what would be generated.
Stdlib only; output is deterministic (sorted keys, 2-space indent, Xcode's `"key" : value` style).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]

# Web language code -> String Catalog / .lproj code. Order is the web picker's order.
LANGUAGES = {"en": "en", "es": "es", "de": "de", "fr": "fr", "hi": "hi", "zh": "zh-Hans", "bn": "bn"}
SOURCE = "en"
PLURAL_SUFFIXES = ("zero", "one", "two", "few", "many", "other")
PLURAL_RE = re.compile(r"^(.+)_(zero|one|two|few|many|other)$")
PLACEHOLDER_RE = re.compile(r"\{\{\s*(\w+)\s*\}\}")

KEYWORDS = frozenset(
    """associatedtype class deinit enum extension fileprivate func import init inout internal let open
    operator private precedencegroup protocol public rethrows static struct subscript typealias var break
    case catch continue default defer do else fallthrough for guard if in repeat return throw switch where
    while Any as await false is nil super throws true try""".split()
)
# Cannot be used as a member name even backticked (`K.x.self`, `.Type`, `.Protocol`): suffix with `_`.
UNUSABLE = frozenset({"self", "Type", "Protocol"})

INFO_PLIST_KEYS = {"location": "NSLocationWhenInUseUsageDescription"}
DISPLAY_NAME = "Voyager"

LOCALIZABLE = Path("Packages/VoyagerKit/Sources/L10n/Resources/Localizable.xcstrings")
KEYS_SWIFT = Path("Packages/VoyagerKit/Sources/L10n/Generated/Keys.swift")
INFO_PLIST = Path("App/Resources/InfoPlist.xcstrings")


class CatalogError(Exception):
    pass


@dataclass
class Entry:
    """One catalogue key: a plain string, or a plural group (forms: suffix -> text)."""

    value: str | None = None
    forms: dict[str, str] | None = None

    @property
    def plural(self) -> bool:
        return self.forms is not None

    def texts(self) -> list[str]:
        return list(self.forms.values()) if self.forms is not None else [self.value or ""]


def flatten(tree: dict, prefix: str = "") -> dict[str, str]:
    """Nested i18next JSON -> {"a.b.c": "text"}. Non-string leaves are an error."""
    out: dict[str, str] = {}
    for name, node in tree.items():
        path = f"{prefix}.{name}" if prefix else name
        if isinstance(node, dict):
            out.update(flatten(node, path))
        elif isinstance(node, str):
            out[path] = node
        else:
            raise CatalogError(f"{path}: expected a string or an object, got {type(node).__name__}")
    return out


def group(flat: dict[str, str]) -> dict[str, Entry]:
    """Collapse `<base>_<suffix>` leaves into one plural Entry per base path."""
    entries: dict[str, Entry] = {}
    for path, text in flat.items():
        m = PLURAL_RE.match(path.rsplit(".", 1)[-1])
        if m:
            base = path[: len(path) - len(m.group(2)) - 1]
            entry = entries.setdefault(base, Entry(forms={}))
            if entry.forms is None:
                raise CatalogError(f"{base}: both a plain key and plural forms")
            entry.forms[m.group(2)] = text
        else:
            if path in entries:
                raise CatalogError(f"{path}: both a plain key and plural forms")
            entries[path] = Entry(value=text)
    return entries


def load_namespaces(directory: Path) -> dict[str, dict[str, Entry]]:
    """`<dir>/<ns>.json` -> {"<ns>:<path>": Entry}."""
    out: dict[str, dict[str, Entry]] = {}
    if not directory.is_dir():
        return out
    for file in sorted(directory.glob("*.json")):
        try:
            tree = json.loads(file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise CatalogError(f"{file}: {exc}") from exc
        if not isinstance(tree, dict):
            raise CatalogError(f"{file}: top level must be an object")
        for path, entry in group(flatten(tree)).items():
            out[f"{file.stem}:{path}"] = entry
    return out


@dataclass
class Result:
    catalog: dict[str, dict[str, Entry]]  # lang -> key -> Entry (complete for every lang)
    placeholders: dict[str, frozenset[str]]
    missing: list[tuple[str, str]]
    pending: int
    extras: list[tuple[str, str]]  # keys a language has that English lacks (ignored)


def build(root: Path) -> Result:
    upstream = root / "Upstream" / "locales"
    per_lang = {lang: load_namespaces(upstream / lang) for lang in LANGUAGES}
    english = per_lang[SOURCE]
    if not english:
        raise CatalogError(f"no English catalogue under {upstream}")

    pending = load_namespaces(root / "i18n" / "pending" / SOURCE)
    collisions = sorted(set(pending) & set(english))
    if collisions:
        raise CatalogError(
            "pending keys already exist upstream (remove them from i18n/pending/en): " + ", ".join(collisions)
        )
    english = {**english, **pending}

    catalog: dict[str, dict[str, Entry]] = {SOURCE: english}
    missing: list[tuple[str, str]] = []
    extras: list[tuple[str, str]] = []
    for lang in LANGUAGES:
        if lang == SOURCE:
            continue
        theirs = per_lang[lang]
        extras += [(lang, key) for key in sorted(set(theirs) - set(english))]
        merged: dict[str, Entry] = {}
        for key, en in english.items():
            entry = theirs.get(key)
            usable = entry is not None and entry.plural == en.plural and (
                not entry.plural or "other" in (entry.forms or {})
            )
            if key in pending:
                merged[key] = en
            elif usable:
                merged[key] = entry  # type: ignore[assignment]
            else:
                merged[key] = en
                missing.append((lang, key))
        catalog[lang] = merged

    placeholders: dict[str, frozenset[str]] = {}
    for key, en in english.items():
        names = {n for text in en.texts() for n in PLACEHOLDER_RE.findall(text)}
        if en.plural:
            names.discard("count")
        placeholders[key] = frozenset(names)
    return Result(catalog, placeholders, missing, len(pending), extras)


# MARK: - Localizable.xcstrings


def _unit(text: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": text}}


def _plural_form(text: str) -> str:
    return PLACEHOLDER_RE.sub(lambda m: "%arg" if m.group(1) == "count" else m.group(0), text.replace("%", "%%"))


def _localization(entry: Entry) -> dict:
    if entry.forms is None:
        return _unit(entry.value or "")
    forms = {
        suffix: _unit(_plural_form(entry.forms[suffix])) for suffix in PLURAL_SUFFIXES if suffix in entry.forms
    }
    return {
        "stringUnit": {"state": "translated", "value": "%#@count@"},
        "substitutions": {
            "count": {"argNum": 1, "formatSpecifier": "lld", "variations": {"plural": forms}}
        },
    }


def localizable(result: Result) -> dict:
    strings = {}
    for key in sorted(result.catalog[SOURCE]):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                code: _localization(result.catalog[lang][key]) for lang, code in LANGUAGES.items()
            },
        }
    return {"sourceLanguage": SOURCE, "strings": strings, "version": "1.0"}


def info_plist(result: Result) -> tuple[dict, bool]:
    """(catalog, has_mobile_namespace). Without `mobile:infoPlist.*` only the display name is emitted."""
    strings = {
        "CFBundleDisplayName": {
            "extractionState": "manual",
            "localizations": {code: _unit(DISPLAY_NAME) for code in LANGUAGES.values()},
        }
    }
    found = False
    for source_key, plist_key in INFO_PLIST_KEYS.items():
        key = f"mobile:infoPlist.{source_key}"
        if key not in result.catalog[SOURCE]:
            continue
        found = True
        strings[plist_key] = {
            "extractionState": "manual",
            "localizations": {
                code: _unit(result.catalog[lang][key].value or "") for lang, code in LANGUAGES.items()
            },
        }
    return {"sourceLanguage": SOURCE, "strings": strings, "version": "1.0"}, found


# MARK: - Keys.swift


def identifier(segment: str) -> str:
    name = re.sub(r"[^0-9A-Za-z_]", "_", segment)
    if not name:
        name = "_"
    if name[0].isdigit():
        name = "_" + name
    if name in UNUSABLE:
        return name + "_"
    return f"`{name}`" if name in KEYWORDS else name


def keys_swift(result: Result) -> str:
    tree: dict = {}
    for key, en in sorted(result.catalog[SOURCE].items()):
        namespace, path = key.split(":", 1)
        node = tree
        parts = [namespace, *path.split(".")]
        for segment in parts[:-1]:
            ident = identifier(segment)
            child = node.setdefault(ident, {})
            if not isinstance(child, dict):
                raise CatalogError(f"{key}: '{segment}' is both a key and a group")
            node = child
        leaf = identifier(parts[-1])
        if leaf in node:
            raise CatalogError(f"{key}: identifier '{leaf}' collides with another key or group")
        placeholders = ", ".join(json.dumps(n) for n in sorted(result.placeholders[key]))
        node[leaf] = (
            f'LKey({json.dumps(key, ensure_ascii=False)}, placeholders: [{placeholders}], '
            f'plural: {"true" if en.plural else "false"})'
        )

    lines = [
        "// Generated by tools/gen_catalog.py from Upstream/locales and i18n/pending. Do not edit.",
        "",
        "public enum K {",
    ]

    def emit(node: dict, depth: int) -> None:
        pad = "    " * depth
        for name in sorted(node, key=lambda n: n.strip("`")):
            value = node[name]
            if isinstance(value, dict):
                lines.append(f"{pad}public enum {name} {{")
                emit(value, depth + 1)
                lines.append(f"{pad}}}")
            else:
                lines.append(f"{pad}public static let {name} = {value}")

    emit(tree, 1)
    lines.append("}")
    return "\n".join(lines) + "\n"


# MARK: - Driver


def dump(data: dict) -> str:
    return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False, separators=(",", " : ")) + "\n"


def outputs(root: Path, result: Result) -> tuple[dict[Path, str], bool]:
    plist, has_mobile = info_plist(result)
    return (
        {
            root / LOCALIZABLE: dump(localizable(result)),
            root / KEYS_SWIFT: keys_swift(result),
            root / INFO_PLIST: dump(plist),
        },
        has_mobile,
    )


def report(result: Result, has_mobile: bool) -> None:
    for lang, key in result.missing:
        print(f"missing: {lang} {key} (using English)", file=sys.stderr)
    for lang, key in result.extras:
        print(f"ignored: {lang} {key} (not in English)", file=sys.stderr)
    print(f"pending: {result.pending} keys", file=sys.stderr)
    if not has_mobile:
        print(
            "notice: no mobile:infoPlist.* keys vendored yet; InfoPlist.xcstrings has only CFBundleDisplayName",
            file=sys.stderr,
        )
    print(
        f"catalog: {len(result.catalog[SOURCE])} keys, {len(LANGUAGES)} languages, "
        f"{len(result.missing)} English fallbacks",
        file=sys.stderr,
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if committed outputs differ")
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root (default: this repo)")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        result = build(root)
        files, has_mobile = outputs(root, result)
    except CatalogError as exc:
        print(f"gen_catalog: {exc}", file=sys.stderr)
        return 1
    report(result, has_mobile)

    if args.check:
        stale = [
            str(path.relative_to(root))
            for path, text in files.items()
            if not path.is_file() or path.read_text(encoding="utf-8") != text
        ]
        if stale:
            print(f"gen_catalog: out of date: {', '.join(stale)} (run tools/gen_catalog.py)", file=sys.stderr)
            return 1
        print("gen_catalog: up to date")
        return 0

    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
