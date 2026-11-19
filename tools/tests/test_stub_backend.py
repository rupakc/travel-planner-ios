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
        assert _call(httpd, "POST", "/api/shares", {"kind": "plan"})[1]["error_code"] == "plan_not_found"
        assert _call(httpd, "POST", "/api/shares", {"kind": "quiz"})[1]["error_code"] == "session_not_found"
        savings = _call(httpd, "POST", "/api/shares", {"kind": "savings"})[1]
        assert savings["title"] == "Price alerts" and _call(httpd, "DELETE", f"/api/shares/{savings['token']}")[0] == 204
        assert _call(httpd, "DELETE", f"/api/shares/{first['token']}")[0] == 204
        assert _call(httpd, "GET", "/api/shares")[1]["shares"] == []
    finally:
        httpd.shutdown()


def test_notification_settings_follow_the_contract():
    httpd = _serve()
    try:
        status, settings = _call(httpd, "GET", "/api/notification-settings")
        assert status == 200 and set(settings["categories"]) == {
            "price_drops", "trip_reminders", "morning_brief", "weather", "nearby", "social", "quiz"}
        assert settings["categories"]["quiz"] == {"enabled": True} and settings["push"] == {"fcm": False, "apns": False}
        assert _call(httpd, "PUT", "/api/notification-settings", {"daily_cap": 0})[0] == 422
        assert _call(httpd, "PUT", "/api/notification-settings", {"daily_cap": 11})[0] == 422
        assert _call(httpd, "PUT", "/api/notification-settings", {"categories": {"nope": {"enabled": True}}})[0] == 422
        assert _call(httpd, "PUT", "/api/notification-settings", {"categories": {"quiz": False}})[0] == 422
        assert _call(httpd, "PUT", "/api/notification-settings", {"quiet_hours": {"enabled": True, "start": "7:00", "end": "08:00"}})[0] == 422
        status, answer = _call(httpd, "PUT", "/api/notification-settings", {"categories": {"quiz": {"enabled": False}}})
        assert status == 200 and answer["categories"]["quiz"] == {"enabled": False}
        assert answer["categories"]["trip_reminders"] == {"enabled": True}
        code = _call(httpd, "PUT", "/api/notification-settings", {"daily_cap": 99})[1]["error_code"]
        assert code == "notification_settings_invalid"
    finally:
        httpd.shutdown()


def test_quiet_hours_are_shared_with_the_alert_prefs():
    httpd = _serve()
    try:
        quiet = {"enabled": True, "start": "23:00", "end": "06:30"}
        assert _call(httpd, "PUT", "/api/notification-settings", {"quiet_hours": quiet})[0] == 200
        assert _call(httpd, "GET", "/api/alerts/preferences")[1]["quiet_hours"] == quiet
        other = {"enabled": False, "start": "21:00", "end": "05:00"}
        assert _call(httpd, "PUT", "/api/alerts/preferences", {"quiet_hours": other})[0] == 200
        assert _call(httpd, "GET", "/api/notification-settings")[1]["quiet_hours"] == other
    finally:
        httpd.shutdown()


def test_notification_catalog_falls_back_to_english():
    httpd = _serve()
    try:
        status, es = _call(httpd, "GET", "/api/notifications/catalog?locale=es")
        assert status == 200 and es["locale"] == "es" and "{place}" in es["templates"]["nearby_arrival"]
        assert _call(httpd, "GET", "/api/notifications/catalog?locale=xx")[1]["locale"] == "en"
        assert all(isinstance(text, str) for text in _call(httpd, "GET", "/api/notifications/catalog")[1]["templates"].values())
    finally:
        httpd.shutdown()


def test_phase5_flags_and_profile_flow():
    httpd = _serve()
    try:
        features = _call(httpd, "GET", "/api/config")[1]["features"]
        assert features["social"] == 1 and features["play"] == 1 and features["game"] is True
        status, profile = _call(httpd, "GET", "/api/social/profile")
        assert status == 200 and profile["handle"] is None and profile["visibility"] == "private"
        assert _call(httpd, "PUT", "/api/social/profile", {"bio": "x"})[0] == 422
        assert _call(httpd, "PUT", "/api/social/profile", {"handle": "pat"})[0] == 409
        assert _call(httpd, "PUT", "/api/social/profile", {"handle": "admin"})[1]["error_code"] == "handle_reserved"
        assert _call(httpd, "GET", "/api/social/handles/check?handle=Maria_K")[1] == {"available": True}
        status, mine = _call(httpd, "PUT", "/api/social/profile", {"handle": "Maria_K", "visibility": "public"})
        assert status == 200 and mine["handle"] == "maria_k" and mine["show_level"] is False
        status, limited = _call(httpd, "PUT", "/api/social/profile", {"handle": "other_name"})
        assert status == 422 and limited["error_code"] == "handle_rate_limited" and limited["retry_after"] > 0
        assert _call(httpd, "PUT", "/api/social/follow/pat")[1] == {"state": "following"}
        assert _call(httpd, "PUT", "/api/social/follow/lena")[1] == {"state": "pending"}
        assert _call(httpd, "GET", "/api/social/profile/nobody")[0] == 404
    finally:
        httpd.shutdown()


def test_phase5_feed_publish_like_comment_report():
    httpd = _serve()
    try:
        assert _call(httpd, "POST", "/api/social/ideas", {"plan_id": 1, "title": "T"})[1]["error_code"] == "profile_required"
        _call(httpd, "PUT", "/api/social/profile", {"handle": "maria_k", "visibility": "public"})
        status, idea = _call(httpd, "POST", "/api/social/ideas", {"plan_id": 1, "title": "Kyoto", "caption": "see http://x"})
        assert status == 200 and idea["status"] == "held" and idea["mine"] is True
        assert _call(httpd, "POST", "/api/social/ideas", {"plan_id": 1, "title": " "})[1]["error_code"] == "title_invalid"
        ideas = _call(httpd, "GET", "/api/social/feed?scope=new")[1]["ideas"]
        assert {i["id"] for i in ideas} == {"i1", idea["id"]}
        assert _call(httpd, "PUT", "/api/social/ideas/i1/like")[0] == 204
        assert _call(httpd, "GET", "/api/social/ideas/i1")[1]["liked"] is True
        assert _call(httpd, "POST", "/api/social/ideas/i1/save")[1]["plan_id"] > 0
        assert _call(httpd, "POST", "/api/social/ideas/i1/comments", {"text": "Nice"})[1]["mine"] is True
        assert len(_call(httpd, "GET", "/api/social/ideas/i1/comments")[1]["comments"]) == 2
        assert _call(httpd, "POST", "/api/social/reports", {"target": "idea", "id": "i1", "reason": "spam"})[0] == 204
        assert _call(httpd, "GET", "/api/social/ideas/zzz")[1]["error_code"] == "idea_not_found"
    finally:
        httpd.shutdown()


def test_phase5_daily_quiz_is_answered_server_side_and_done_once():
    httpd = _serve()
    try:
        status, session = _call(httpd, "POST", "/api/play/quiz", {"mode": "daily"})
        assert status == 200 and len(session["questions"]) == 5 and session["questions"][0]["options"][0]["code"] == "JP"
        sid = session["session_id"]
        last = None
        for index in range(5):
            last = _call(httpd, "POST", f"/api/play/quiz/{sid}/answer", {"index": index, "choice": "a"})[1]
        assert last["done"] is True and last["summary"]["correct"] == 5 and last["summary"]["xp"]["xp"] == 10
        assert _call(httpd, "POST", "/api/play/quiz", {"mode": "daily"})[1]["error_code"] == "already_done"
        state = _call(httpd, "GET", "/api/play/state")[1]
        assert state["daily"]["done"] is True and state["daily"]["score"] == last["summary"]["score"]
        assert _call(httpd, "POST", "/api/play/quiz", {"mode": "pack", "pack": "nope"})[1]["error_code"] == "invalid_pack"
        assert _call(httpd, "GET", "/api/play/quiz/missing")[1]["error_code"] == "session_not_found"
        assert len(_call(httpd, "GET", "/api/play/history")[1]["history"]) == 1
    finally:
        httpd.shutdown()


def test_phase5_head_to_head_and_boards():
    httpd = _serve()
    try:
        assert _call(httpd, "POST", "/api/play/h2h", {"handle": "pat", "pack": "flags"})[0] == 409
        _call(httpd, "PUT", "/api/social/profile", {"handle": "maria_k", "visibility": "public"})
        assert _call(httpd, "POST", "/api/play/h2h", {"handle": "maria_k", "pack": "flags"})[1]["error_code"] == "cannot_challenge_self"
        status, created = _call(httpd, "POST", "/api/play/h2h", {"handle": "pat", "pack": "flags"})
        assert status == 200 and created["id"] == "m1" and created["mode"] == "h2h"
        match = _call(httpd, "GET", "/api/play/h2h")[1]["matches"][0]
        assert match["state"] == "waiting_them" and match["them"] is None and match["session_id"] == created["session_id"]
        board = _call(httpd, "GET", "/api/play/leaderboard?scope=global&week=current")[1]
        assert board["week"] == "2026-W46" and board["you"]["rank"] is None
        _call(httpd, "PUT", "/api/social/profile", {"leaderboard_opt_in": True})
        assert _call(httpd, "GET", "/api/play/leaderboard?scope=global")[1]["you"]["rank"] == 2
        assert _call(httpd, "GET", "/api/play/challenge")[1]["kind"] == "featured"
    finally:
        httpd.shutdown()


def test_phase5_catalog_has_the_social_and_quiz_templates():
    httpd = _serve()
    try:
        templates = _call(httpd, "GET", "/api/notifications/catalog")[1]["templates"]
        assert {"idea_saved", "new_follower", "h2h_invite", "h2h_result"} <= set(templates)
    finally:
        httpd.shutdown()


def test_base_sign_in_and_launch_routes():
    httpd = _serve()
    status, login = _call(httpd, "POST", "/api/auth/login", {"username": "smoke", "password": "anything"})
    assert status == 200 and login["user"]["username"] == "smoke" and login["access_token"].count(".") == 2
    assert _call(httpd, "GET", "/api/auth/me")[1]["requires_password_change"] is False
    status, watches = _call(httpd, "GET", "/api/fare-watches")
    assert status == 200 and watches[0]["id"] == 7 and watches[0]["last_price"] < watches[0]["baseline_price"]
    assert _call(httpd, "GET", "/api/notifications/unread-count") == (200, {"count": 0})


def test_legacy_plan_share_create_list_and_revoke():
    httpd = _serve()
    assert _call(httpd, "GET", "/api/shares")[1]["legacy_plan_shares"] == []
    status, created = _call(httpd, "POST", "/api/plans/1/share")
    assert status == 200 and created["share_token"]
    legacy = _call(httpd, "GET", "/api/shares")[1]["legacy_plan_shares"]
    assert legacy == [{"plan_id": 1, "name": "Lisbon in May", "url": f"https://stub.invalid/share/{created['share_token']}"}]
    assert _call(httpd, "DELETE", "/api/plans/1/share") == (200, {"success": True})
    assert _call(httpd, "GET", "/api/shares")[1]["legacy_plan_shares"] == []
    assert _call(httpd, "POST", "/api/plans/99/share")[0] == 404


def test_carbon_flag_and_trip_report():
    httpd = _serve()
    try:
        _, config = _call(httpd, "GET", "/api/config")
        assert config["features"]["carbon"] == 1
        status, report = _call(httpd, "POST", "/api/carbon/trip", {"diet": "mixed", "flights": []})
        assert status == 200 and report["total_kg"] == 420 and report["categories"][0]["key"] == "flights"
        assert _call(httpd, "POST", "/api/carbon/trip", ["not", "an", "object"])[0] == 422
    finally:
        httpd.shutdown()



def test_carbon_module_loads_beside_a_phase():
    assert server.ALL_PHASES[-1] == "carbon"
    _, config = server.Stub(("phase4", "carbon")).dispatch("GET", "/api/config", {}, None)
    assert config["features"]["carbon"] == 1 and config["features"]["sharing"] == 1
