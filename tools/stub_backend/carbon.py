"""Carbon stub: `POST /api/carbon/trip` (travel-planner `docs/Carbon-Footprint.md`) with a canned report.

`features.carbon` is `1`, as the backend sends it. No factors are computed: any object body gets the same answer,
anything else is `422`.
"""
from __future__ import annotations

FEATURES = {"carbon": 1}

REPORT = {
    "total_kg": 420, "per_person_kg": 210, "travellers": 2, "nights": 4, "diet": "mixed", "cabin": "economy",
    "categories": [
        {"key": "flights", "kg": 300, "share": 0.7143, "included": True},
        {"key": "stays", "kg": 80, "share": 0.1905, "included": True},
        {"key": "food", "kg": 40, "share": 0.0952, "included": True},
    ],
    "lines": [
        {"category": "flights", "kind": "flight_distance", "label": "Flight", "kg": 300, "method": "distance_based",
         "params": {"from": "LHR", "to": "CDG", "km": 344, "cabin": "economy"}},
    ],
    "comparisons": {"car_km": 1750, "trees_years": 19},
    "lower_carbon": [],
    "sources": [{"name": "UK DESNZ greenhouse gas conversion factors", "url": "https://www.gov.uk/government/collections/government-conversion-factors-for-company-reporting"}],
    "assumptions": [],
    "factors_version": "stub",
}


def reset(state):
    state["carbon_calls"] = 0


def handle(method, path, query, body, state):
    if path != "/api/carbon/trip":
        return None
    if method != "POST":
        return 405, {"detail": "Method Not Allowed"}
    if not isinstance(body, dict):
        return 422, {"detail": "invalid carbon request"}
    state["carbon_calls"] += 1
    return 200, REPORT
