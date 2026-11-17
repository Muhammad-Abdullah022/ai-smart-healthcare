"""Medicine search with same-salt alternatives (features 30, 37) and the pharmacy finder (feature 28).

Safety: alternatives are medicines with the SAME salt (active ingredient). Strength and form must still
match what the doctor prescribed, so the app always says "ask your pharmacist before switching".
If a brand is not in the app's list, the AI may suggest its salt — clearly marked as an AI guess.
"""
import re

from fastapi import APIRouter, Depends, Query, Request, status
from pydantic import BaseModel, Field

from app.ai.service import AIUnavailableError
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db
from app.pharmacy import key
from app.routers.assessments import get_ai_service

router = APIRouter(tags=["medicine database", "pharmacies"])

SWITCH_NOTE = ("Same salt means the same active medicine. Before switching, check with your pharmacist that the "
               "strength and form match your prescription.")


def _brand(d: dict) -> dict:
    return {"brand": d["brand"], "generic": d["generic"], "company": d.get("company", ""),
            "forms": d.get("forms", []), "strengths": d.get("strengths", [])}


def _generic(g: dict | None) -> dict | None:
    if not g:
        return None
    return {"generic": g["generic"], "drug_class": g["drug_class"], "uses": g["uses"],
            "side_effects": g["side_effects"], "warnings": g["warnings"]}


@router.get("/drugs/search")
async def search(q: str = Query(min_length=1, max_length=60), limit: int = Query(30, ge=1, le=100),
                 user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Brands whose name starts with / contains the text, or whose salt matches it."""
    k = key(q)
    if not k:
        return {"results": []}
    rx = re.escape(k)
    starts, contains = [], []
    async for d in db.medicine_brands.find({"$or": [{"brand_key": {"$regex": rx}}, {"generic_key": {"$regex": rx}}]}).limit(400):
        (starts if d["brand_key"].startswith(k) else contains).append(d)
    starts.sort(key=lambda d: d["brand_key"])
    contains.sort(key=lambda d: (not d["generic_key"].startswith(k), d["brand_key"]))
    return {"results": [_brand(d) for d in (starts + contains)[:limit]]}


class AISaltGuess(BaseModel):
    found: bool
    brand: str = Field(default="", max_length=80)
    generic: str = Field(default="", max_length=160)
    drug_class: str = Field(default="", max_length=120)
    uses: str = Field(default="", max_length=240)


SALT_SYSTEM = """You identify medicines sold in Pakistan. Given a brand name, return its active ingredient(s)
(salt / generic name) in standard English, e.g. "Naproxen" or "Amoxicillin + Clavulanic Acid".
Set found=false if you are not sure the brand exists. Never give doses. Reply only as JSON:
{"found": true|false, "brand": "...", "generic": "...", "drug_class": "...", "uses": "..."}"""


@router.get("/drugs/detail")
async def detail(request: Request, name: str = Query(min_length=2, max_length=80),
                 user: dict = Depends(get_current_user), db=Depends(get_db)):
    """One medicine: salt info + every other brand with the same salt. Unknown brands: AI guesses the salt."""
    k = key(name)
    brand = await db.medicine_brands.find_one({"brand_key": k})
    ai_guess = False
    if brand:
        generic_key, generic_name = brand["generic_key"], brand["generic"]
    else:
        g = await db.medicine_generics.find_one({"generic_key": k})
        if g:  # the user typed a salt name
            generic_key, generic_name = g["generic_key"], g["generic"]
        else:
            try:
                res = await get_ai_service(request).generate(AISaltGuess, SALT_SYSTEM, f"Brand: {name}")
            except AIUnavailableError as exc:
                raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_unavailable", exc.message)
            if not res.data.found or not res.data.generic.strip():
                raise ApiError(status.HTTP_404_NOT_FOUND, "not_found",
                               "This medicine is not in the app's list. Please ask your pharmacist.")
            ai_guess = True
            generic_name = res.data.generic.strip()
            generic_key = key(generic_name)
            brand = {"brand": res.data.brand or name, "generic": generic_name, "company": "", "forms": [],
                     "strengths": []}
    info = _generic(await db.medicine_generics.find_one({"generic_key": generic_key}))
    if info is None and ai_guess:
        info = {"generic": generic_name, "drug_class": res.data.drug_class, "uses": res.data.uses,
                "side_effects": "", "warnings": ""}
    alternatives = [_brand(d) async for d in db.medicine_brands.find({"generic_key": generic_key}).sort("brand_key", 1)
                    if not brand or d["brand_key"] != key(brand["brand"])]
    return {"medicine": _brand(brand) if brand and "brand" in brand else None, "generic": info,
            "alternatives": alternatives, "ai_guess": ai_guess, "note": SWITCH_NOTE}


@router.get("/drugs/stats")
async def stats(user: dict = Depends(get_current_user), db=Depends(get_db)):
    return {"brands": await db.medicine_brands.count_documents({}),
            "generics": await db.medicine_generics.count_documents({})}


@router.get("/pharmacies")
async def pharmacies(city: str = Query(min_length=2, max_length=60), q: str | None = Query(None, max_length=60),
                     open_24h: bool = False, user: dict = Depends(get_current_user), db=Depends(get_db)):
    flt: dict = {"city_key": key(city)}
    if open_24h:
        flt["open_24h"] = True
    if q and key(q):
        flt["name_key"] = {"$regex": re.escape(key(q))}
    docs = [d async for d in db.pharmacies.find(flt)]
    order = {"chain": 0, "independent": 1, "government": 2}
    docs.sort(key=lambda d: (d["demo"], order.get(d["kind"], 3), d["name"]))
    return {"city": city, "pharmacies": [
        {"name": d["name"], "address": d["address"], "phone": d["phone"], "hours": d["hours"], "kind": d["kind"],
         "open_24h": d["open_24h"], "source": d["source"], "demo": d["demo"]} for d in docs],
        "note": "Stock is not shown live — please call the pharmacy to check if your medicine is available."}
