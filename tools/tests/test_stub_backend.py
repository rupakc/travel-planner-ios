"""tools/stub_backend: the dispatcher merges every phase's feature flags and each phase answers its routes."""
import json
import sys
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

STUB = Path(__file__).resolve().parents[1] / "stub_backend"
sys.path.insert(0, str(STUB))
import server  # noqa: E402


def _serve(phases=server.ALL_PHASES):
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.make_handler(server.Stub(phases)))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def _call(httpd, method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{httpd.server_address[1]}{path}", data=data, method=method,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"null")


def test_config_merges_phase_flags():
    httpd = _serve()
    try:
        status, config = _call(httpd, "GET", "/api/config")
        assert status == 200
        features = config["features"]
        assert features["alerts_api"] == 2 and features["sharing"] == 1 and features["notifications_api"] == 1
    finally:
        httpd.shutdown()


def test_only_listed_phases_are_on():
    httpd = _serve(("phase4",))
    try:
        _, config = _call(httpd, "GET", "/api/config")
        assert "alerts_api" not in config["features"] and config["features"]["sharing"] == 1
        assert _call(httpd, "GET", "/api/alerts/summary")[0] == 404
    finally:
        httpd.shutdown()


def test_alert_prefs_round_trip_and_invalid():
    httpd = _serve()
    try:
        status, prefs = _call(httpd, "PUT", "/api/alerts/preferences", {"digest_weekly": True, "timezone": "UTC"})
        assert status == 200 and prefs["digest_weekly"] is True and prefs["timezone"] == "Asia/Kolkata"
        assert _call(httpd, "PUT", "/api/alerts/preferences", {"daily_cap": {"flight": 11}})[0] == 422
        assert _call(httpd, "GET", "/api/alerts/watches/flight/7/story")[1]["advice"]["code"] == "near_target"
    finally:
        httpd.shutdown()


def test_quick_watch_pending_existing_and_errors():
    httpd = _serve()
    try:
        body = {"kind": "hotel", "title": "Lumen Hotel", "spec": {"name": "Lumen"}, "surface": "results"}
        status, first = _call(httpd, "POST", "/api/alerts/quick-watch", body)
        assert status == 201 and first["existing"] is False
        assert first["watch"]["pending_first_check"] is True and first["watch"]["last_price"] is None
        status, again = _call(httpd, "POST", "/api/alerts/quick-watch", body)
        assert status == 200 and again["existing"] is True and again["watch"]["id"] == first["watch"]["id"]
        assert _call(httpd, "POST", "/api/alerts/quick-watch", {"kind": "boat", "title": "x", "spec": {}})[0] == 422
        status, tip = _call(httpd, "POST", "/api/alerts/watches/flight/7/advice")
        assert status == 200 and tip["source"] == "ai"
        assert _call(httpd, "POST", "/api/alerts/watches/hotel/7/advice")[1]["error_code"] == "advice_unsupported"
        _, summary = _call(httpd, "GET", "/api/alerts/summary")
        assert summary["drops_caught"] == 1 and summary["next_milestone"] == 50
    finally:
        httpd.shutdown()


def test_alert_prefs_validation_quiet_flag_errors_and_unsubscribe():
    httpd = _serve()
    try:
        for bad in ({"instant": "never"}, {"digest_day": 8}, {"group_window_min": 121}, {"quiet_hours": {"enabled": True, "start": "25:00", "end": "07:00"}}):
            status, body = _call(httpd, "PUT", "/api/alerts/preferences", bad)
            assert status == 422 and body["error_code"] == "alert_prefs_invalid", bad
        status, prefs = _call(httpd, "PUT", "/api/alerts/preferences", {"quiet_hours": {"enabled": False, "start": "22:00", "end": "07:00"}})
        assert status == 200 and prefs["quiet_hours_active"] is False
        assert _call(httpd, "GET", "/api/alerts/watches/flight/950/story")[1]["error_code"] == "watch_not_found"
        assert _call(httpd, "GET", "/api/alerts/watches/boat/1/story")[1]["error_code"] == "kind_invalid"
        body = {"kind": "hotel", "title": "x", "spec": {"a": 1}, "plan_id": 901, "surface": "trip"}
        assert _call(httpd, "POST", "/api/alerts/quick-watch", body)[1]["error_code"] == "trip_not_found"
        _call(httpd, "PUT", "/api/alerts/preferences", {"digest_weekly": True})
        assert _call(httpd, "GET", "/api/alerts/digest/unsubscribe")[0] == 200
        assert _call(httpd, "GET", "/api/alerts/preferences")[1]["digest_weekly"] is False
    finally:
        httpd.shutdown()


def test_share_create_is_idempotent_and_revoke_removes():
    httpd = _serve()
    try:
        _, first = _call(httpd, "POST", "/api/shares", {"kind": "plan", "plan_id": 5})
        status, again = _call(httpd, "POST", "/api/shares", {"kind": "plan", "plan_id": 5, "options": {"dates": "month"}})
        assert status == 200 and again["token"] == first["token"] and again["options"]["dates"] == "month"
        assert _call(httpd, "POST", "/api/shares", {"kind": "nope"})[0] == 422
        assert _call(httpd, "DELETE", f"/api/shares/{first['token']}")[0] == 204
        assert _call(httpd, "GET", "/api/shares")[1]["shares"] == []
    finally:
        httpd.shutdown()


def test_notification_settings_validate_cap():
    httpd = _serve()
    try:
        assert _call(httpd, "PUT", "/api/notifications/settings", {"daily_cap": 0})[0] == 422
        status, settings = _call(httpd, "PUT", "/api/notifications/settings", {"categories": {"quiz": False}})
        assert status == 200 and settings["categories"]["quiz"] is False and settings["categories"]["trip"] is True
    finally:
        httpd.shutdown()
