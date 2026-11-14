"""Phase 3 stub: price alerts 2.0 (`Alerts-API.md`). Canned data only, never a price source."""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

FEATURES = {"alerts_api": 2, "price_alerts_v2": True, "live_prices": True}

PREFS = {
    "digest_weekly": False, "digest_push": False, "digest_day": 1, "instant": "all",
    "quiet_hours": {"enabled": True, "start": "22:00", "end": "07:00"},
    "daily_cap": {"flight": 3, "hotel": 3, "activity": 3, "trip": 3}, "group_window_min": 15,
    "timezone": "Asia/Kolkata", "quiet_hours_active": False,
}
READ_ONLY = {"timezone", "quiet_hours_active"}


def _live_prices_off(state):
    return bool(state.get("live_prices_off") or os.environ.get("STUB_LIVE_PRICES_OFF"))


def _quiet_active(prefs, now=None):
    """Mirror of the contract: false without a usable timezone, when disabled, or when start == end."""
    quiet = prefs.get("quiet_hours") or {}
    try:
        zone = ZoneInfo(prefs.get("timezone") or "")
    except Exception:
        return False
    if not quiet.get("enabled") or quiet.get("start") == quiet.get("end"):
        return False
    local = (now or datetime.now(timezone.utc)).astimezone(zone).strftime("%H:%M")
    start, end = quiet.get("start", ""), quiet.get("end", "")
    return start <= local < end if start < end else (local >= start or local < end)


def _valid_hhmm(value):
    try:
        datetime.strptime(value, "%H:%M")
        return True
    except (TypeError, ValueError):
        return False


def _prefs_invalid(patch):
    if "instant" in patch and patch["instant"] not in ("all", "targets_only"):
        return True
    day = patch.get("digest_day")
    if "digest_day" in patch and (not isinstance(day, int) or isinstance(day, bool) or not 1 <= day <= 7):
        return True
    window = patch.get("group_window_min")
    if "group_window_min" in patch and (not isinstance(window, int) or isinstance(window, bool) or not 0 <= window <= 120):
        return True
    for key in ("digest_weekly", "digest_push"):
        if key in patch and not isinstance(patch[key], bool):
            return True
    quiet = patch.get("quiet_hours")
    if "quiet_hours" in patch and (
        not isinstance(quiet, dict) or not isinstance(quiet.get("enabled"), bool)
        or not _valid_hhmm(quiet.get("start")) or not _valid_hhmm(quiet.get("end"))
    ):
        return True
    cap = patch.get("daily_cap")
    if "daily_cap" in patch and (
        not isinstance(cap, dict)
        or any(k not in ("flight", "hotel", "activity", "trip") or not isinstance(v, int) or isinstance(v, bool)
               or not 1 <= v <= 10 for k, v in cap.items())
    ):
        return True
    return False


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
    if _live_prices_off(state):
        return 503, {"detail": "Price watching isn't available right now.", "error_code": "live_prices_off"}
    plan_id = body.get("plan_id")
    if isinstance(plan_id, int) and plan_id >= 900:
        return 404, {"detail": "Trip not found", "error_code": "trip_not_found"}
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
            state["alert_prefs"]["quiet_hours_active"] = _quiet_active(state["alert_prefs"])
            return 200, state["alert_prefs"]
        if method == "PUT":
            patch = {k: v for k, v in (body or {}).items() if k not in READ_ONLY}
            if _prefs_invalid(patch):
                return 422, {"detail": "invalid", "error_code": "alert_prefs_invalid"}
            state["alert_prefs"].update(patch)
            state["alert_prefs"]["quiet_hours_active"] = _quiet_active(state["alert_prefs"])
            return 200, state["alert_prefs"]
    if path == "/api/alerts/digest/unsubscribe" and method in ("GET", "POST"):
        state["alert_prefs"]["digest_weekly"] = False
        return 200, {"unsubscribed": True}
    parts = path.strip("/").split("/")
    watch_route = len(parts) == 6 and parts[:3] == ["api", "alerts", "watches"] and parts[5] in ("story", "advice")
    if watch_route and parts[3] not in ("flight", "hotel", "activity", "trip"):
        return 422, {"detail": "Unknown kind", "error_code": "kind_invalid"}
    if watch_route and parts[4].isdigit() and int(parts[4]) >= 900:
        return 404, {"detail": "Watch not found", "error_code": "watch_not_found"}
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
        if _live_prices_off(state):
            return 503, {"detail": "Price watching isn't available right now.", "error_code": "live_prices_off"}
        return 200, {"suggestions": [], "live_prices": True}
    return None
