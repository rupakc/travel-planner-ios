#!/usr/bin/env python3
"""Export the web's closed telemetry registry to JSON.

    tools/export_registry.py <registry.py> <out.json>

Loads ``backend/app/telemetry/registry.py`` (vendored as ``Upstream/registry.py``)
by path, with no backend imports, and writes
``{"events": {name: {prop: type}}, "platforms": [...]}`` with sorted keys.
The iOS Telemetry tests compare the SDK's events and props with this file.
"""

import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # loading the registry must not leave __pycache__ in Upstream/


def load_registry(path: Path):
    spec = importlib.util.spec_from_file_location("_voyager_telemetry_registry", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"export_registry: cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def export(registry: Path) -> dict:
    module = load_registry(registry)
    for attr in ("EVENTS", "_PLATFORMS"):
        if not hasattr(module, attr):
            raise SystemExit(f"export_registry: {registry} has no {attr}")
    events = {name: dict(props) for name, props in module.EVENTS.items()}
    return {"events": events, "platforms": sorted(module._PLATFORMS)}


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    data = export(Path(argv[1]))
    out = Path(argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
