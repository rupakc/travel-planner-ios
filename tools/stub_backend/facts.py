"""Place facts stub: `POST /api/place-facts` (travel-planner `docs/Place-Facts.md`) with a canned section.

`features.place_facts` is `1`, as the backend sends it. One place with a sourced crawler fact (citation, as-of,
licence attribution) and an AI-suggested fact (no citation); any object body gets the same answer, anything
else is `422`.
"""
from __future__ import annotations

FEATURES = {"place_facts": 1}


def _groups(**facts):
    groups = {name: [] for name in ("historical", "fun", "popular", "unbelievable", "little_known")}
    groups.update(facts)
    return groups


SECTION = {
    "places": [
        {
            "key": "city:2950159", "scope": "city", "name": "Berlin", "country": "DE", "country_name": "Germany",
            "destination": "Berlin, Germany", "geonames_id": 2950159,
            "groups": _groups(
                historical=[{
                    "id": "c:1", "fact_type": "historical", "text": "Berlin was founded in 1237.",
                    "origin": "crawler", "source": "crawler", "date_ref": "1237", "lang": "en", "value_lang": None,
                    "machine_translated": False, "confidence": "structured",
                    "citation": {
                        "source_id": "od-wikidata-entitydata", "name": "Wikidata",
                        "publisher": "Wikidata contributors (Wikimedia Foundation)",
                        "url": "https://www.wikidata.org/wiki/Q64#P571", "as_of": "2026-11-20", "licence": "open",
                        "attribution": "Wikidata (CC0 1.0)", "licence_url": None, "conflict": False,
                    },
                }],
                fun=[{
                    "id": "a:3f9c0b1d2e4a", "fact_type": "fun", "text": "Berlin has a museum just for currywurst.",
                    "origin": "ai", "source": "ai", "verified": False, "citation": None,
                }],
            ),
        },
    ],
    "fact_types": ["historical", "fun", "popular", "unbelievable", "little_known"],
    "counts": {"crawler": 1, "ai": 1},
    "verification": {"level": "partial", "label": "Partly sourced", "summary": "", "checks": [], "pending": False},
}


def reset(state):
    state["place_facts_calls"] = 0


def handle(method, path, query, body, state):
    if path != "/api/place-facts":
        return None
    if method != "POST":
        return 405, {"detail": "Method Not Allowed"}
    if not isinstance(body, dict):
        return 422, {"detail": "invalid search request"}
    state["place_facts_calls"] += 1
    return 200, SECTION
