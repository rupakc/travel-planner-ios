"""Phase 5 stub: social and Play (`Social-API.md`). In-memory, deterministic, no AI, no network.

The caller is one signed-in user. Option `a` is always the right answer, so a smoke test can answer without reading the
question. Pass `{"state": ...}` reset via `POST /__reset`.
"""
from __future__ import annotations

import re

FEATURES = {"social": 1, "play": 1, "game": True}

HANDLE = re.compile(r"^[a-z0-9_]{3,20}$")
RESERVED = {"admin", "voyager", "support", "moderator"}
REASONS = ("spam", "abuse", "sexual", "violence", "misinformation", "other")
PACKS = ("flags", "capitals", "landmarks", "cuisine")

OTHERS = {
    "pat": {"handle": "pat", "bio": "Trains and ramen", "visibility": "public", "ideas_count": 1, "followers_count": 4, "following_count": 2},
    "lena": {"handle": "lena", "bio": "", "visibility": "followers", "ideas_count": 0, "followers_count": 1, "following_count": 1},
}


def reset(state):
    state["profile"] = {
        "handle": None, "visibility": "private", "bio": "", "show_avatar": False, "show_home_country": False,
        "show_countries": False, "show_level": False, "show_badges": False, "leaderboard_opt_in": False,
        "home_country": None, "created_at": None,
    }
    state["following"] = {}
    state["blocked"] = set()
    state["ideas"] = {
        "i1": {
            "id": "i1", "kind": "plan", "title": "Tokyo in five days", "caption": "Ramen first.", "author": {"handle": "pat"},
            "snapshot": {"days": 5, "destinations": ["Tokyo"]}, "likes": 3, "saves": 1, "comments": 1, "liked": False,
            "saved": False, "mine": False, "status": "published", "created_at": "2026-11-10T09:00:00Z",
        }
    }
    state["comments"] = {"i1": [{"id": "c1", "author": {"handle": "lena"}, "text": "Saving this.", "helpful": False, "mine": False,
                                 "created_at": "2026-11-10T10:00:00Z"}]}
    state["idea_seq"] = 1
    state["reports"] = []
    state["sessions"] = {}
    state["session_seq"] = 0
    state["daily_done"] = None
    state["matches"] = {}


def _error(status, code, detail, **extra):
    return status, {"detail": detail, "error_code": code, **extra}


def _questions(pack):
    return [
        {
            "index": i, "kind": "flag" if pack == "flags" else "capital",
            "prompt": {"template": "flag", "code": "JP"} if pack == "flags" else {"template": "capital_of", "capital": "Tokyo"},
            "options": [{"id": "a", "label": "Japan", "code": "JP"}, {"id": "b", "label": "Laos", "code": "LA"},
                        {"id": "c", "label": "Chad", "code": "TD"}, {"id": "d", "label": "Fiji", "code": "FJ"}],
        }
        for i in range(5)
    ]


def _new_session(state, mode, pack, match_id=None):
    state["session_seq"] += 1
    sid = f"stubsession{state['session_seq']:03d}"
    session = {"session_id": sid, "mode": mode, "pack": pack, "questions": _questions(pack or "flags"),
               "expires_at": "2026-11-15T12:00:00Z", "answers": [], "done": False, "resumed": False}
    if match_id:
        session["id"] = match_id
    state["sessions"][sid] = session
    return session


def _view(session):
    view = dict(session)
    view["answers"] = list(session["answers"])
    return view


def _handle_social(method, path, query, body, state):
    parts = path.strip("/").split("/")[2:]  # after api/social
    me = state["profile"]
    if parts == ["profile"] and method == "GET":
        return 200, me
    if parts == ["profile"] and method == "PUT":
        body = body or {}
        if me["handle"] is None and "handle" not in body:
            return _error(422, "handle_invalid", "Pick a handle to create a profile.")
        handle = body.get("handle")
        if handle is not None:
            handle = handle.lower()
            if not HANDLE.match(handle):
                return _error(422, "handle_invalid", "Handles are 3 to 20 letters, numbers or underscores.")
            if handle in RESERVED:
                return _error(422, "handle_reserved", "That handle is reserved.")
            if handle in OTHERS:
                return _error(409, "handle_taken", "That handle is taken.")
            if me["handle"] and handle != me["handle"]:
                return _error(422, "handle_rate_limited", "You can change your handle once every 30 days.", retry_after=2592000)
            me["handle"] = handle
            me["created_at"] = me["created_at"] or "2026-11-14T10:00:00Z"
        for key in ("visibility", "bio", "show_avatar", "show_home_country", "show_countries", "show_level", "show_badges",
                    "leaderboard_opt_in", "home_country"):
            if key in body:
                me[key] = body[key]
        return 200, me
    if parts == ["handles", "check"] and method == "GET":
        handle = query.get("handle", "").lower()
        if not HANDLE.match(handle):
            return 200, {"available": False, "reason": "invalid"}
        if handle in RESERVED:
            return 200, {"available": False, "reason": "reserved"}
        if handle in OTHERS or handle == me["handle"]:
            return 200, {"available": False, "reason": "taken"}
        return 200, {"available": True}
    if len(parts) == 2 and parts[0] == "profile" and method == "GET":
        other = OTHERS.get(parts[1])
        if other is None or other["visibility"] == "private" or parts[1] in state["blocked"]:
            return _error(404, "profile_not_found", "Profile not found.")
        following = state["following"].get(parts[1])
        profile = {k: other[k] for k in ("handle", "bio", "ideas_count", "followers_count", "following_count")}
        profile["you"] = {"following": following == "following", "pending": following == "pending", "follows_you": False,
                          "blocked": False}
        return 200, profile
    if len(parts) == 2 and parts[0] == "follow":
        if method == "PUT":
            if me["handle"] is None:
                return _error(403, "profile_required", "Create a profile first.")
            other = OTHERS.get(parts[1])
            if other is None or parts[1] in state["blocked"]:
                return _error(404, "profile_not_found", "Profile not found.")
            state["following"][parts[1]] = "following" if other["visibility"] == "public" else "pending"
            return 200, {"state": state["following"][parts[1]]}
        if method == "DELETE":
            state["following"].pop(parts[1], None)
            return 204, None
    if parts == ["follow-requests"] and method == "GET":
        return 200, {"requests": []}
    if len(parts) == 3 and parts[0] == "follow-requests" and method == "POST":
        return _error(404, "request_not_found", "No such follow request.")
    if parts in (["followers"], ["following"]) and method == "GET":
        users = [{"handle": h} for h, s in state["following"].items() if s == "following"] if parts == ["following"] else []
        return 200, {"users": users, "next": None}
    if len(parts) == 2 and parts[0] == "block":
        if method == "PUT":
            state["blocked"].add(parts[1])
            state["following"].pop(parts[1], None)
        else:
            state["blocked"].discard(parts[1])
        return 204, None
    if parts == ["blocks"] and method == "GET":
        return 200, {"users": [{"handle": h} for h in sorted(state["blocked"])]}
    if parts == ["feed"] and method == "GET":
        ideas = [i for i in state["ideas"].values() if i["status"] == "published" or i["mine"]]
        return 200, {"ideas": ideas, "next": None}
    if parts == ["ideas"] and method == "POST":
        return _publish(body or {}, state)
    if len(parts) >= 2 and parts[0] == "ideas":
        return _idea_routes(method, parts, body or {}, state)
    if len(parts) == 2 and parts[0] == "comments" and method == "DELETE":
        return 204, None
    if parts == ["reports"] and method == "POST":
        body = body or {}
        if body.get("reason") not in REASONS:
            return _error(422, "content_rejected", "That reason is not recognised.")
        state["reports"].append(body)
        return 204, None
    return None


def _publish(body, state):
    me = state["profile"]
    if me["handle"] is None or me["visibility"] == "private":
        return _error(403, "profile_required", "Make your profile visible first.")
    title = (body.get("title") or "").strip()
    if not title:
        return _error(422, "title_invalid", "Give the idea a title.")
    state["idea_seq"] += 1
    idea_id = f"i{state['idea_seq']}"
    held = "http" in (body.get("caption") or "")
    idea = {
        "id": idea_id, "kind": body.get("kind", "plan"), "title": title[:80], "caption": (body.get("caption") or "")[:500],
        "author": {"handle": me["handle"]}, "snapshot": {"days": 3}, "likes": 0, "saves": 0, "comments": 0, "liked": False,
        "saved": False, "mine": True, "status": "held" if held else "published", "created_at": "2026-11-14T10:00:00Z",
    }
    state["ideas"][idea_id] = idea
    return 200, idea


def _idea_routes(method, parts, body, state):
    idea = state["ideas"].get(parts[1])
    if idea is None:
        return _error(404, "idea_not_found", "Idea not found.")
    tail = parts[2:]
    if tail == [] and method == "GET":
        return 200, idea
    if tail == [] and method == "DELETE":
        state["ideas"].pop(parts[1])
        return 204, None
    if tail == ["like"]:
        liked = method == "PUT"
        if liked != idea["liked"]:
            idea["likes"] += 1 if liked else -1
        idea["liked"] = liked
        return 204, None
    if tail == ["save"] and method == "POST":
        idea["saved"] = True
        idea["saves"] += 1
        return 200, {"plan_id": 900 + int(parts[1].lstrip("i") or 0)}
    if tail == ["save"] and method == "DELETE":
        idea["saved"] = False
        return 204, None
    if tail == ["comments"] and method == "GET":
        return 200, {"comments": state["comments"].get(parts[1], []), "next": None}
    if tail == ["comments"] and method == "POST":
        text = (body.get("text") or "").strip()
        if not text:
            return _error(422, "text_invalid", "Write a comment first.")
        comment = {"id": f"c{len(state['comments'].get(parts[1], [])) + 2}", "author": {"handle": state["profile"]["handle"] or "me"},
                   "text": text[:300], "helpful": False, "mine": True, "created_at": "2026-11-14T10:00:00Z"}
        state["comments"].setdefault(parts[1], []).append(comment)
        idea["comments"] += 1
        return 200, comment
    return None


def _handle_play(method, path, query, body, state):
    parts = path.strip("/").split("/")[2:]  # after api/play
    if parts == ["state"] and method == "GET":
        done = state["daily_done"]
        return 200, {
            "daily": {"available": done is None, "done": done is not None, "score": done,
                      "streak": {"current": 1 if done else 0, "longest": 3, "freeze_available": True}},
            "packs": [{"id": p, "title_key": f"play.pack.{p}", "questions": 40} for p in PACKS],
            "challenge": {"id": "2026-W46:featured", "kind": "featured", "title_key": "play.challenge.featured.flags", "done": False},
            "open_h2h": sum(1 for m in state["matches"].values() if m["state"] == "waiting_you"),
        }
    if parts == ["quiz"] and method == "POST":
        body = body or {}
        mode = body.get("mode")
        if mode == "daily":
            if state["daily_done"] is not None:
                return _error(409, "already_done", "You already played today's quiz.")
            return 200, _view(_new_session(state, "daily", None))
        if mode == "pack":
            if body.get("pack") not in PACKS:
                return _error(422, "invalid_pack", "Unknown pack.")
            return 200, _view(_new_session(state, "pack", body["pack"]))
        if mode == "challenge":
            return 200, _view(_new_session(state, "challenge", "flags"))
        return _error(422, "invalid_mode", "Unknown mode.")
    if len(parts) >= 2 and parts[0] == "quiz":
        session = state["sessions"].get(parts[1])
        if session is None:
            return _error(404, "session_not_found", "Quiz session not found.")
        if len(parts) == 2 and method == "GET":
            return 200, _view(session)
        if len(parts) == 3 and parts[2] == "answer" and method == "POST":
            return _answer(session, body or {}, state)
    if parts == ["history"] and method == "GET":
        done = [s for s in state["sessions"].values() if s["done"]]
        return 200, {"history": [{"session_id": s["session_id"], "mode": s["mode"], "pack": s["pack"], "score": s["score"],
                                  "correct": s["correct"], "finished_at": "2026-11-14T11:00:00Z"} for s in done]}
    if parts == ["h2h"] and method == "GET":
        return 200, {"matches": [{k: v for k, v in m.items() if not k.startswith("_")} for m in state["matches"].values()]}
    if parts == ["h2h"] and method == "POST":
        return _h2h_create(body or {}, state)
    if parts == ["leaderboard"] and method == "GET":
        week = "2026-W46" if query.get("week", "current") == "current" else "2026-W45"
        me = state["profile"]
        rows = [{"rank": 1, "handle": "pat", "score": 900, "you": False}]
        you = None
        if me["handle"]:
            you = {"rank": 2 if me["leaderboard_opt_in"] else None, "score": 500, "opted_in": me["leaderboard_opt_in"]}
            if me["leaderboard_opt_in"]:
                rows.append({"rank": 2, "handle": me["handle"], "score": 500, "you": True})
        return 200, {"week": week, "rows": rows, "you": you}
    if parts == ["challenge"] and method == "GET":
        return 200, {"id": "2026-W46:featured", "kind": "featured", "title_key": "play.challenge.featured.flags", "done": False}
    return None


def _answer(session, body, state):
    index = body.get("index")
    if not isinstance(index, int) or not 0 <= index < 5:
        return _error(422, "invalid_index", "No such question.")
    if any(a["index"] == index for a in session["answers"]):
        return _error(422, "out_of_order", "Already answered.")
    correct = body.get("choice") == "a"
    points = 140 if correct else 0
    session["answers"].append({"index": index, "choice": body.get("choice"), "correct": correct, "correct_choice": "a", "points": points})
    result = {"correct": correct, "correct_choice": "a", "points": points, "elapsed_ms": 1500, "done": False}
    if len(session["answers"]) == 5:
        session["done"] = True
        session["score"] = sum(a["points"] for a in session["answers"])
        session["correct"] = sum(1 for a in session["answers"] if a["correct"])
        summary = {"score": session["score"], "correct": session["correct"], "total": 5,
                   "xp": {"xp": 10, "awards": [{"rule": "quiz_daily", "points": 10}], "badges": [], "level_up": None},
                   "streak": {"current": 1, "longest": 3, "freeze_available": True}}
        session["summary"] = summary
        result["done"] = True
        result["summary"] = summary
        if session["mode"] == "daily":
            state["daily_done"] = session["score"]
    return 200, result


def _h2h_create(body, state):
    me = state["profile"]
    if me["handle"] is None:
        return _error(409, "profile_required", "Create a profile with a handle to challenge.")
    handle = (body.get("handle") or "").lower()
    if handle == me["handle"]:
        return _error(422, "cannot_challenge_self", "You cannot challenge yourself.")
    if handle not in OTHERS or OTHERS[handle]["visibility"] == "private":
        return _error(404, "profile_not_found", "Profile not found.")
    if body.get("pack") not in PACKS:
        return _error(422, "invalid_pack", "Unknown pack.")
    match_id = f"m{len(state['matches']) + 1}"
    session = _new_session(state, "h2h", body["pack"], match_id)
    state["matches"][match_id] = {"id": match_id, "opponent": {"handle": handle}, "pack": body["pack"], "state": "waiting_them",
                                  "you": None, "them": None, "winner": None, "expires_at": "2026-11-16T10:00:00Z",
                                  "session_id": session["session_id"]}
    return 200, _view(session)


def handle(method, path, query, body, state):
    if path.startswith("/api/social/"):
        return _handle_social(method, path, query, body, state)
    if path.startswith("/api/play/"):
        return _handle_play(method, path, query, body, state)
    return None
