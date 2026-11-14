#!/usr/bin/env python3
"""Stub Voyager backend for the iOS UI smoke tests (stdlib only, no credentials, no network).

    python3 tools/stub_backend/server.py [--port 8765] [--phases 3,4,6]

One dispatcher, one module per phase (`phase3.py`, `phase4.py`, `phase6.py`; phase 5 arrives with its core
task). A phase module exposes `FEATURES` (merged into `GET /api/config` `features`) and
`handle(method, path, query, body, state) -> (status, json) | None`. The first module that answers wins; anything
else is `404 {"detail": "not found"}`. `GET /__calls` lists the requests seen, `POST /__reset` clears the state.
"""
from __future__ import annotations

import argparse
import importlib
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))

ALL_PHASES = ("phase3", "phase4", "phase6")


class Stub:
    def __init__(self, phases=ALL_PHASES):
        self.modules = [importlib.import_module(name) for name in phases]
        self.reset()

    def reset(self):
        self.calls = []
        self.state = {}
        for module in self.modules:
            module.reset(self.state)

    def config(self):
        features = {"accounts": True}
        for module in self.modules:
            features.update(module.FEATURES)
        return {"public_base_url": "", "telemetry": {"enabled": False}, "features": features}

    def dispatch(self, method, path, query, body):
        self.calls.append(f"{method} {path}")
        if method == "GET" and path == "/api/config":
            return 200, self.config()
        if method == "GET" and path == "/__calls":
            return 200, {"calls": self.calls}
        if method == "POST" and path == "/__reset":
            self.reset()
            return 200, {"ok": True}
        for module in self.modules:
            answer = module.handle(method, path, query, body, self.state)
            if answer is not None:
                return answer
        return 404, {"detail": "not found", "error_code": "not_found"}


def make_handler(stub):
    class Handler(BaseHTTPRequestHandler):
        def _run(self, method):
            parts = urlsplit(self.path)
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b""
            try:
                body = json.loads(raw) if raw else None
            except ValueError:
                body = None
            query = {k: v[0] for k, v in parse_qs(parts.query).items()}
            status, payload = stub.dispatch(method, parts.path, query, body)
            data = b"" if status == 204 else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):  # noqa: N802
            self._run("GET")

        def do_POST(self):  # noqa: N802
            self._run("POST")

        def do_PUT(self):  # noqa: N802
            self._run("PUT")

        def do_DELETE(self):  # noqa: N802
            self._run("DELETE")

        def log_message(self, *args):
            pass

    return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--phases", default="3,4,6")
    args = parser.parse_args(argv)
    phases = tuple(f"phase{n.strip()}" for n in args.phases.split(",") if n.strip())
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(Stub(phases)))
    print(f"stub backend on http://127.0.0.1:{server.server_address[1]}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
