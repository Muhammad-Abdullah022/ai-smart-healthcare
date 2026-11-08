"""Features 5–7: tests in plain English, labs in the user's city and their published prices.

Only sourced data (backend/data/labs) is shown, each price with its source and check date.
"""
from fastapi import APIRouter, Depends, Query

from app.deps import get_current_user, get_db
from app.labs.catalog import ENGLISH_NAME, family_of
from app.labs.loader import _key

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
async def lab_options(city: str, tests: list[str] = Query(default=[]), user: dict = Depends(get_current_user),
                      db=Depends(get_db)):
    """For each suggested test: its English name and up to 5 labs in the city, cheapest published price first."""
    ck = _key(city)
    labs = {lab["lab_key"]: lab async for lab in db.labs.find({"city_key": ck})}
    known_city = await db.lab_locations.find_one({"city_key": ck}) is not None

    def lab_info(lab_key: str, fallback_name: str) -> dict:
        lab = labs.get(lab_key) or {}
        return {"lab": lab.get("lab_name", fallback_name), "branch": lab.get("branch", ""),
                "address": lab.get("address", ""), "phone": lab.get("phone", ""), "lab_type": lab.get("lab_type", "")}

    results = []
    for asked in tests[:5]:
        fam = family_of(asked)
        offers = []
        if fam:
            async for p in db.lab_prices.find({"city_key": ck, "family": fam}):
                offers.append({**lab_info(p["lab_key"], p["lab_name"]), "published_name": p["test_name"],
                               "price_pkr": p["price_pkr"], "source_url": p["source_url"],
                               "checked": p["checked"], "notes": p["notes"]})
        offers.sort(key=lambda o: (o["price_pkr"] is None, o["price_pkr"] or 0))
        results.append({"asked": asked, "family": fam, "name_en": ENGLISH_NAME.get(fam, asked), "offers": offers[:5]})

    priced_labs = {o["lab"] for r in results for o in r["offers"]}
    other_labs = [{"lab": lab["lab_name"], "branch": lab["branch"], "address": lab["address"],
                   "phone": lab["phone"], "lab_type": lab["lab_type"], "source_url": lab["source_url"],
                   "checked": lab["checked"]}
                  for lab in labs.values() if lab["lab_name"] not in priced_labs][:5]
    return {"city": city, "known_city": known_city, "tests": results,
            "labs_without_prices": other_labs, "note": PRICE_NOTE, "directory_url": DIRECTORY_URL}
