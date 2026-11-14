"""Phase 3 stub: price alerts 2.0 (`Alerts-API.md`). Canned data only, never a price source."""
from __future__ import annotations

import json

FEATURES = {"alerts_api": 2, "price_alerts_v2": True, "live_prices": True}

PREFS = {
    "digest_weekly": False, "digest_push": False, "digest_day": 1, "instant": "all",
    "quiet_hours": {"enabled": True, "start": "22:00", "end": "07:00"},
    "daily_cap": {"flight": 3, "hotel": 3, "activity": 3, "trip": 3}, "group_window_min": 15,
    "timezone": "Asia/Kolkata", "quiet_hours_active": False,
}
READ_ONLY = {"timezone", "quiet_hours_active"}


def reset(state):
    state["alert_prefs"] = dict(PREFS)
    state["quick_watches"] = []


def _story(kind, watch_id):
    return {
        "kind": kind, "watch_id": watch_id, "currency": "USD", "mode": "below_target", "target": 380.0,
        "points": [
            {"at": "2026-11-01T08:00:00Z", "price": 455.0},
            {"at": "2026-11-08T08:00:00Z", "price": 412.0},
        ],
        "baseline": 455.0, "latest": {"at": "2026-11-08T08:00:00Z", "price": 412.0},
        "lowest": {"at": "2026-11-08T08:00:00Z", "price": 412.0},
        "typical": {"low": 390.0, "high": 520.0, "source": "google"}, "verdict": "good",
        "advice": {"code": "near_target", "params": {"gap": 32.0}},
        "checked_at": "2026-11-08T08:00:00Z", "checked_days_ago": 0, "next_check_at": "2026-11-09T08:00:00Z",
        "pending_first_check": False, "estimate": None, "caught": 43.0, "live_prices": True,
    }


def _quick_watch(body, state):
    kind, spec = body.get("kind"), body.get("spec")
    if kind not in ("flight", "hotel", "activity", "trip") or not isinstance(spec, dict) or not body.get("title"):
        return 422, {"detail": "invalid spec", "error_code": "spec_invalid"}
    watches = state.setdefault("quick_watches", [])
    key = (kind, json.dumps(spec, sort_keys=True))
    for index, (existing_key, watch) in enumerate(watches):
        if existing_key == key:
            return 200, {"kind": kind, "watch": watch, "existing": True}
    if len(watches) >= 20:
        return 409, {"detail": "You have reached the watch limit", "error_code": "watch_limit"}
    watch = {"id": 100 + len(watches), "status": "active", "alert_mode": "any_drop", "email_enabled": False,
             "last_price": None, "pending_first_check": True, "title": body["title"]}
    watches.append((key, watch))
    return 201, {"kind": kind, "watch": watch, "existing": False}


def handle(method, path, query, body, state):
    if path == "/api/alerts/summary" and method == "GET":
        return 200, {
            "total_usd": 43.0, "by_currency": {}, "drops_caught": 1, "targets_hit": 0, "watches_active": 1,
            "best": {"kind": "flight", "watch_id": 7, "title": "NYC to Lisbon", "caught": 43.0, "currency": "USD"},
            "milestones": [50, 200, 1000], "next_milestone": 50, "progress_pct": 86, "since": "2026-11-03T08:00:00Z",
        }
    if path == "/api/alerts/preferences":
        if method == "GET":
            return 200, state["alert_prefs"]
        if method == "PUT":
            patch = {k: v for k, v in (body or {}).items() if k not in READ_ONLY}
            cap = patch.get("daily_cap") or {}
            if any(not isinstance(v, int) or not 1 <= v <= 10 for v in cap.values()):
                return 422, {"detail": "invalid", "error_code": "alert_prefs_invalid"}
            state["alert_prefs"].update(patch)
            return 200, state["alert_prefs"]
    parts = path.strip("/").split("/")
    if method == "GET" and len(parts) == 6 and parts[:3] == ["api", "alerts", "watches"] and parts[5] == "story":
        return 200, _story(parts[3], int(parts[4]) if parts[4].isdigit() else 0)
    if method == "POST" and len(parts) == 6 and parts[:3] == ["api", "alerts", "watches"] and parts[5] == "advice":
        if parts[3] != "flight":
            return 422, {"detail": "Advice is for flights only", "error_code": "advice_unsupported"}
        return 200, {"tip": "Prices are near your target; waiting a few days is low risk.", "source": "ai",
                     "generated_at": "2026-11-08T08:00:00Z", "cached": False}
    if path == "/api/alerts/quick-watch" and method == "POST":
        return _quick_watch(body or {}, state)
    if path == "/api/alerts/suggestions" and method == "GET":
        return 200, {"suggestions": [], "live_prices": True}
    return None
