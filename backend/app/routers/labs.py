"""Features 5–7: tests in plain English, labs in the user's city and their published prices.

Only sourced data (backend/data/labs) is shown, each price with its source and check date.
"""
from fastapi import APIRouter, Depends, Query

from app.deps import get_current_user, get_db
from app.labs.catalog import ENGLISH_NAME, family_of
from app.labs.loader import ALL_CITIES, _key

router = APIRouter(prefix="/labs", tags=["labs"])

DIRECTORY_URL = "https://os.phc.org.pk/Registered_Labs.aspx"
PRICE_NOTE = ("Prices are from each lab's own published list (checked on the date shown). "
              "They can change and may differ by branch — please confirm with the lab before you go.")


@router.get("/cities")
async def cities(user: dict = Depends(get_current_user), db=Depends(get_db)):
    """All supported cities/tehsils, with how many sourced labs each has."""
    counts: dict[str, int] = {}
    async for lab in db.labs.find({}, {"city_key": 1}):
        counts[lab["city_key"]] = counts.get(lab["city_key"], 0) + 1
    out = [{"city": c["city"], "district": c["district"], "division": c["division"],
            "labs": counts.get(c["city_key"], 0)} async for c in db.lab_locations.find({})]
    return sorted(out, key=lambda c: (-c["labs"], c["city"]))


@router.get("/options")
async def lab_options(city: str, tests: list[str] = Query(default=[]), other_limit: int = Query(8, ge=0, le=2000),
                      user: dict = Depends(get_current_user), db=Depends(get_db)):
    """For each suggested test: its English name and up to 5 labs in the city, cheapest published price first.

    A chain's branches in the city are shown once (with the branch count); chain-wide prices apply to them.
    """
    ck = _key(city)
    branches: dict[str, list[dict]] = {}
    async for lab in db.labs.find({"city_key": ck}):
        branches.setdefault(lab["lab_key"], []).append(lab)
    known_city = await db.lab_locations.find_one({"city_key": ck}) is not None

    def lab_info(lab_key: str, fallback_name: str) -> dict:
        group = branches.get(lab_key) or [{}]
        first = group[0]
        n = len(group)
        return {"lab": first.get("lab_name", fallback_name),
                "branch": f"{n} branches in {city}" if n > 1 else first.get("branch", ""),
                "address": first.get("address", "") + (" (one of the branches)" if n > 1 else ""),
                "phone": first.get("phone", ""), "lab_type": first.get("lab_type", ""), "branches": n}

    results = []
    for asked in tests[:8]:
        fam = family_of(asked)
        offers, seen = [], set()
        if fam:
            query = {"family": fam, "$or": [{"city_key": ck},
                                            {"city_key": ALL_CITIES, "lab_key": {"$in": list(branches)}}]}
            async for p in db.lab_prices.find(query):
                offers.append({**lab_info(p["lab_key"], p["lab_name"]), "published_name": p["test_name"],
                               "price_pkr": p["price_pkr"], "discount_price_pkr": p.get("discount_price_pkr"),
                               "source_url": p["source_url"], "checked": p["checked"], "notes": p["notes"]})
        # One row per lab: its cheapest matching test (the user can still see the lab's own test name).
        offers.sort(key=lambda o: (o["price_pkr"] is None, o["price_pkr"] or 0))
        unique = []
        for o in offers:
            if o["lab"] not in seen:
                seen.add(o["lab"])
                unique.append(o)
        results.append({"asked": asked, "family": fam, "name_en": ENGLISH_NAME.get(fam, asked), "offers": unique[:5]})

    priced_labs = {o["lab"] for r in results for o in r["offers"]}
    other_labs = []
    for key, group in branches.items():
        info = lab_info(key, group[0]["lab_name"])
        if info["lab"] not in priced_labs:
            other_labs.append({**info, "source_url": group[0]["source_url"], "checked": group[0]["checked"]})
    other_labs.sort(key=lambda o: (-o["branches"], not o["phone"], o["lab"].lower()))
    return {"city": city, "known_city": known_city, "tests": results,
            "labs_without_prices": other_labs[:other_limit], "other_total": len(other_labs),
            "note": PRICE_NOTE, "directory_url": DIRECTORY_URL}
