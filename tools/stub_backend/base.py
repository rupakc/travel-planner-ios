"""Base stub: sign-in and the few classic routes the app reads on every launch (`docs/Accounts-API.md`, `API-Reference.md`).

Always loaded, after the phase modules. Canned data only: one user (`smoke` / any password), one saved plan that has a
legacy share token, one flight watch with a drop. A route this module does not know answers 404 from the dispatcher.
"""
from __future__ import annotations

import base64
import json

FEATURES: dict = {}

USER = {"username": "smoke", "is_admin": False, "requires_password_change": False, "email": "smoke@example.invalid"}


def _token():
    """A JWT-shaped string that expires far in the future (the app reads `exp` to schedule a refresh)."""
    def part(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")
    return f"{part({'alg': 'none'})}.{part({'sub': 'smoke', 'exp': 4102444800})}.stub"


def reset(state):
    state["plans"] = [{
        "id": 1, "name": "Lisbon in May", "created_at": "2026-11-01T09:00:00Z", "updated_at": "2026-11-01T09:00:00Z",
        "search_data": {"destination": "Lisbon", "origin": "NYC"}, "selections": {}, "share_token": None,
    }]
    state["fare_watches"] = [{
        "id": 7, "origin_code": "JFK", "destination_code": "LIS", "origin_label": "New York", "destination_label": "Lisbon",
        "departure_date": "2026-12-10", "return_date": "2026-12-17", "num_travelers": 1, "cabin": "economy",
        "flexible_days": 0, "alert_mode": "any_drop", "email_enabled": False, "status": "active",
        "baseline_price": 455.0, "last_price": 412.0, "lowest_price": 412.0, "lowest_price_date": "2026-11-08",
        "check_count": 2, "failure_count": 0, "last_checked_at": "2026-11-08T08:00:00Z", "next_check_at": "2026-11-09T08:00:00Z",
        "created_at": "2026-11-01T08:00:00Z", "updated_at": "2026-11-08T08:00:00Z",
        "history": [{"checked_at": "2026-11-01T08:00:00Z", "price": 455.0}, {"checked_at": "2026-11-08T08:00:00Z", "price": 412.0}],
    }]


def handle(method, path, query, body, state):
    if path == "/api/auth/login" and method == "POST":
        return 200, {"access_token": _token(), "token_type": "bearer", "user": USER}
    if path == "/api/auth/me" and method == "GET":
        return 200, USER
    if path == "/api/auth/providers" and method == "GET":
        return 200, {"providers": []}
    if path == "/api/plans" and method == "GET":
        return 200, [{k: v for k, v in p.items() if k not in ("search_data", "selections")} for p in state["plans"]]
    if path == "/api/fare-watches" and method == "GET":
        return 200, state["fare_watches"]
    if path == "/api/price-watches" and method == "GET":
        return 200, []
    if path == "/api/notifications" and method == "GET":
        return 200, {"items": [], "total": 0, "unread": 0}
    if path == "/api/notifications/unread-count" and method == "GET":
        return 200, {"count": 0}
    if path == "/api/recent-searches" and method == "GET":
        return 200, []
    if path == "/api/devices" and method == "GET":
        return 200, []
    if path == "/api/preferences" and method == "GET":
        return 200, {}
    return None
