"""Phase 3 stub: price alerts 2.0 (`Alerts-API.md`). Canned data only, never a price source."""
from __future__ import annotations

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


def handle(method, path, query, body, state):
    if path == "/api/alerts/summary" and method == "GET":
        return 200, {
            "total_usd": 43.0, "by_currency": {}, "count": 1, "watches_active": 1,
            "next_milestone": 50, "recent": [],
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
    if path == "/api/alerts/suggestions" and method == "GET":
        return 200, {"suggestions": [], "live_prices": True}
    return None
