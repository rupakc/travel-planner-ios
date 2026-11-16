"""Phase 6 stub: notifications 2.0 (`Notifications-API.md`). No push is ever sent; canned data only."""
from __future__ import annotations

import re

FEATURES = {"notifications_api": 1, "notifications_v2": True, "apns": False}

CATEGORIES = ("price_drops", "trip_reminders", "morning_brief", "weather", "nearby", "social", "quiz")
CLOCK = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")

CATALOG = {
    "en": {
        "trip_t30": "{destination} is {days} days away. Check your visa and entry rules.",
        "trip_t7": "{days} days to {destination}. Time to pack.",
        "trip_t1": "Tomorrow you fly to {destination}. Check in and review the weather.",
        "trip_morning": "Good morning from {destination}. Open Today for your plan.",
        "nearby_arrival": "You're near {place}: {item} is {minutes} min away",
        "weather_rain": "Rain is likely around {time}: take an umbrella for {slot}.",
        "idea_saved": "{handle} saved your idea {title}.",
        "new_follower": "{handle} started following you.",
        "h2h_invite": "{handle} challenged you to a {pack} quiz.",
        "h2h_result": "Your quiz match with {handle} is done.",
    },
    "es": {"nearby_arrival": "Estás cerca de {place}: {item} está a {minutes} min"},
}


def reset(state):
    state["notif_settings"] = {
        "categories": {name: {"enabled": True} for name in CATEGORIES},
        "quiet_hours": {"enabled": True, "start": "22:00", "end": "07:00"},
        "daily_cap": 3, "timezone": "Asia/Kolkata", "quiet_hours_active": False,
        "push": {"fcm": False, "apns": False}, "devices": 0,
    }


def _invalid():
    return 422, {"detail": "invalid notification settings", "error_code": "notification_settings_invalid"}


def _view(state):
    """The full settings object. Quiet hours are the alert prefs' value when that phase is loaded (one shared value)."""
    settings = dict(state["notif_settings"])
    prefs = state.get("alert_prefs")
    if prefs is not None:
        settings["quiet_hours"] = prefs["quiet_hours"]
        settings["quiet_hours_active"] = prefs.get("quiet_hours_active", False)
    return settings


def _quiet_ok(quiet):
    return (
        isinstance(quiet, dict) and isinstance(quiet.get("enabled"), bool)
        and all(isinstance(quiet.get(key), str) and CLOCK.match(quiet[key]) for key in ("start", "end"))
        and set(quiet) <= {"enabled", "start", "end"}
    )


def _put(state, patch):
    if not isinstance(patch, dict):
        return _invalid()
    settings = state["notif_settings"]
    categories = patch.get("categories", {})
    if not isinstance(categories, dict):
        return _invalid()
    for name, value in categories.items():
        if name not in CATEGORIES or not isinstance(value, dict) or not isinstance(value.get("enabled"), bool):
            return _invalid()
    cap = patch.get("daily_cap", settings["daily_cap"])
    if not isinstance(cap, int) or isinstance(cap, bool) or not 1 <= cap <= 10:
        return _invalid()
    if "quiet_hours" in patch and not _quiet_ok(patch["quiet_hours"]):
        return _invalid()
    # Read-only keys (timezone, quiet_hours_active, push, devices) are ignored; anything else is unknown.
    known = {"categories", "quiet_hours", "daily_cap", "timezone", "quiet_hours_active", "push", "devices"}
    if set(patch) - known:
        return _invalid()
    for name, value in categories.items():
        settings["categories"][name] = {"enabled": value["enabled"]}
    if "quiet_hours" in patch:
        settings["quiet_hours"] = dict(patch["quiet_hours"])
        if "alert_prefs" in state:
            state["alert_prefs"]["quiet_hours"] = dict(patch["quiet_hours"])
    settings["daily_cap"] = cap
    return 200, _view(state)


def handle(method, path, query, body, state):
    if path == "/api/notification-settings":
        if method == "GET":
            return 200, _view(state)
        if method == "PUT":
            return _put(state, body)
    if path == "/api/notifications/catalog" and method == "GET":
        locale = query.get("locale", "en")
        if locale not in CATALOG:
            locale = "en"
        return 200, {"locale": locale, "templates": CATALOG[locale]}
    return None
