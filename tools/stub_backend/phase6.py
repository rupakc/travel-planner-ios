"""Phase 6 stub: notifications 2.0 (`Notifications-API.md`). No push is ever sent."""
from __future__ import annotations

FEATURES = {"notifications_api": 1, "notifications_v2": True, "apns": False}

CATEGORIES = ("price", "trip", "weather", "nearby", "social", "quiz", "system")


def reset(state):
    state["notif_settings"] = {
        "categories": {name: True for name in CATEGORIES},
        "quiet_hours": {"enabled": True, "start": "22:00", "end": "07:00"},
        "daily_cap": 3, "timezone": "Asia/Kolkata", "push": {"fcm": False, "apns": False}, "devices": 0,
    }


def handle(method, path, query, body, state):
    if path == "/api/notifications/settings":
        settings = state["notif_settings"]
        if method == "GET":
            return 200, settings
        if method == "PUT":
            patch = body or {}
            cap = patch.get("daily_cap", settings["daily_cap"])
            if not isinstance(cap, int) or not 1 <= cap <= 10:
                return 422, {"detail": "invalid", "error_code": "notification_settings_invalid"}
            settings["categories"].update(patch.get("categories") or {})
            if "quiet_hours" in patch:
                settings["quiet_hours"] = patch["quiet_hours"]
            settings["daily_cap"] = cap
            return 200, settings
    if path == "/api/notifications/catalog" and method == "GET":
        return 200, {
            "locale": query.get("locale", "en"),
            "templates": {"nearby_arrival": {"title": "Near you", "body": "{item} is {minutes} min from {place}"}},
        }
    return None
