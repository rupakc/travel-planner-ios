"""Phase 4 stub: share links 2.0 (`Sharing-API.md`). In-memory shares; no card PNGs are served."""
from __future__ import annotations

FEATURES = {"sharing": 1}

KINDS = ("plan", "recap", "savings", "quiz", "status")


def reset(state):
    state["shares"] = {}
    state["share_seq"] = 0


def _share(state, kind, plan_id, options):
    key = (kind, plan_id if kind != "savings" else None)
    for share in state["shares"].values():
        if (share["kind"], share["plan_id"]) == key:
            share["options"] = options  # a second POST replaces the options of the same link
            return 200, share
    state["share_seq"] += 1
    token = f"stubtoken{state['share_seq']:04d}"
    share = {
        "token": token, "kind": kind, "plan_id": key[1], "options": options,
        "url": f"https://stub.invalid/share/{token}", "created_at": "2026-11-10T09:00:00Z",
        "card_url": {
            "link": f"https://stub.invalid/api/share/{token}/card.png?size=link",
            "story": f"https://stub.invalid/api/share/{token}/card.png?size=story",
        },
    }
    state["shares"][token] = share
    return 201, share


def handle(method, path, query, body, state):
    if path == "/api/shares" and method == "POST":
        body = body or {}
        if body.get("kind") not in KINDS:
            return 422, {"detail": "invalid kind", "error_code": "invalid_kind"}
        options = {"dates": "hidden", "show_origin": False, "show_name": False}
        options.update(body.get("options") or {})
        return _share(state, body["kind"], body.get("plan_id"), options)
    if path == "/api/shares" and method == "GET":
        return 200, {"shares": list(reversed(list(state["shares"].values()))), "legacy_plan_shares": []}
    parts = path.strip("/").split("/")
    if len(parts) == 3 and parts[:2] == ["api", "shares"] and method == "DELETE":
        if state["shares"].pop(parts[2], None) is None:
            return 404, {"detail": "not found", "error_code": "share_not_found"}
        return 204, None
    if len(parts) == 3 and parts[:2] == ["api", "share"] and method == "GET":
        share = state["shares"].get(parts[2])
        if share is None:
            return 404, {"detail": "not found", "error_code": "share_not_found"}
        return 200, {
            "kind": share["kind"], "options": share["options"],
            "card": {"headline": "Stub trip", "stats": [{"key": "countries", "count": 2}]},
        }
    return None
