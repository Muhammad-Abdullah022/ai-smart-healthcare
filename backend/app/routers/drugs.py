"""Medicine search with same-salt alternatives (features 30, 37) and the pharmacy finder (feature 28).

Safety: alternatives are medicines with the SAME salt (active ingredient). Strength and form must still
match what the doctor prescribed, so the app always says "ask your pharmacist before switching".
If a brand is not in the app's list, the AI may suggest its salt — clearly marked as an AI guess.
"""
import base64
import re

from fastapi import APIRouter, Depends, File, Query, Request, UploadFile, status
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
            "forms": d.get("forms", []), "strengths": d.get("strengths", []), "source": d.get("source", "")}


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


# ---------- Feature 29: price comparison (official DRAP prices) ----------

PRICE_NOTE = ("Prices are DRAP's official maximum retail prices (2021 list) — the same in every city. DRAP has "
              "revised some prices since then, so today's shop price can be higher. Confirm at the pharmacy, and "
              "ask your pharmacist before switching brands.")
_SYNONYMS = {"amoxycillin": "amoxicillin", "pheneramine": "pheniramine", "acetylsalicylic": "aspirin",
             "acetyl": "aspirin", "orphenadine": "orphenadrine", "esomperazole": "esomeprazole"}
_SKIP_WORDS = {"acid", "sodium", "potassium", "calcium", "hydrochloride", "hcl", "as", "and", "with", "tablet",
               "tablets", "capsule", "syrup", "the", "plus", "forte"}


def _words(text: str) -> set[str]:
    out = set()
    for w in key(text).split():
        w = _SYNONYMS.get(w, w)
        if len(w) > 3 and w not in _SKIP_WORDS and not w[0].isdigit():
            out.add(w)
    return out


def _strength_num(text: str) -> str | None:
    m = re.search(r"(\d+(?:\.\d+)?)", text or "")
    if not m:
        return None
    n = m.group(1)
    return n.rstrip("0").rstrip(".") if "." in n else n


def _is_combo(row: dict) -> bool:
    f = row["formulation"]
    return bool(re.search(r"\+|&|;| and ", f)) or len({s.split()[0] for s in row["strengths"]}) > 2


async def _pharmacies_in(db, city: str, limit: int = 12) -> list[dict]:
    docs = [d async for d in db.pharmacies.find({"city_key": key(city)})]
    order = {"chain": 0, "independent": 1, "government": 2}
    docs.sort(key=lambda d: (d["demo"], order.get(d["kind"], 3), d["name"]))
    return [{"name": d["name"], "address": d["address"], "phone": d["phone"], "hours": d["hours"],
             "kind": d["kind"], "open_24h": d["open_24h"], "demo": d["demo"]} for d in docs[:limit]]


@router.get("/drugs/prices")
async def prices(name: str = Query(min_length=2, max_length=80), strength: str = Query("", max_length=40),
                 city: str = Query("", max_length=60), user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Every brand with the same medicine (salt), cheapest first, plus pharmacies in the user's city."""
    from app.medicine_prices import SOURCE_NAME, SOURCE_PAGE

    k = key(name)
    if not k:
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "bad_name", "Type a medicine name.")
    loaded = await db.medicine_prices.count_documents({}) > 0
    # Which salt is it? A known brand -> its salt; a priced brand -> its formulation; else the text itself.
    generic = ""
    brand = await db.medicine_brands.find_one({"brand_key": k}) or await db.medicine_brands.find_one(
        {"brand_key": {"$regex": "^" + re.escape(k)}})
    if brand:
        generic = brand["generic"]
    elif g := await db.medicine_generics.find_one({"generic_key": k}):
        generic = g["generic"]
    else:
        row = await db.medicine_prices.find_one({"brand_key": {"$regex": "^" + re.escape(k)}})
        if row:
            generic = row["formulation"] if not _is_combo(row) else ""
    salt_words = _words(generic) or _words(name)
    rx = re.escape(k)
    rows = []
    async for r in db.medicine_prices.find({}):
        hay = _words(f"{r['brand']} {r['formulation']}")
        by_brand = re.search(rf"\b{rx}", r["brand_key"]) is not None
        by_salt = bool(salt_words) and salt_words <= hay
        if by_brand or by_salt:
            rows.append(r)
    num = _strength_num(strength)
    combo_query = "+" in generic or len(salt_words) > 1
    items = []
    for r in rows:
        same_strength = bool(num) and any(s.split()[0] == num for s in r["strengths"])
        if not same_strength and num and re.search(rf"(?<![\d.]){re.escape(num)}(?![\d.])", r["brand"]):
            same_strength = True
        items.append({
            "brand": r["brand"], "company": r["company"], "formulation": r["formulation"], "pack": r["pack"],
            "form": r["form"], "strengths": r["strengths"], "mrp": r["mrp"], "units": r["units"],
            "per_unit": r["per_unit"], "same_strength": same_strength,
            "combo": _is_combo(r) and not combo_query})
    items.sort(key=lambda i: (i["combo"], not i["same_strength"] if num else False, i["mrp"] is None,
                              i["per_unit"] if i["per_unit"] is not None else (i["mrp"] or 0) * 1000, i["brand"]))
    priced = [i for i in items if i["mrp"] and not i["combo"] and (i["same_strength"] or not num)]
    cheapest = min(priced, key=lambda i: i["per_unit"] if i["per_unit"] is not None else i["mrp"]) if priced else None
    gk = key(generic)
    shown = {key(i["brand"]).split()[0] for i in items if key(i["brand"])}
    unpriced = []
    if gk:
        async for b in db.medicine_brands.find({"generic_key": gk}).sort("brand_key", 1).limit(40):
            if b["brand_key"].split()[0] not in shown:
                unpriced.append({"brand": b["brand"], "company": b.get("company", ""),
                                 "strengths": b.get("strengths", []), "forms": b.get("forms", [])})
    return {
        "query": name, "generic": generic, "strength": strength, "city": city,
        "items": items[:60], "cheapest": cheapest, "other_brands": unpriced[:20],
        "pharmacies": await _pharmacies_in(db, city) if city.strip() else [],
        "price_list_loaded": loaded, "note": PRICE_NOTE,
        "source": {"name": SOURCE_NAME, "url": SOURCE_PAGE},
    }


# ---------- Medicine search by photo (box / strip) ----------

class AIMedicinePhoto(BaseModel):
    found: bool
    brand: str = Field(default="", max_length=80)
    generic: str = Field(default="", max_length=160)
    strength: str = Field(default="", max_length=40)
    form: str = Field(default="", max_length=30)
    unclear: str = Field(default="", max_length=200)


PHOTO_SYSTEM = """You read the name printed on a medicine box, strip, bottle or tube in a photo (Pakistan).
Return the brand name exactly as printed, its active ingredient(s) (salt) in English, the strength printed
(e.g. "500 mg") and the form (tablet, capsule, syrup, cream, drops, injection, inhaler, other).
Do not guess: if the name is not readable set found=false and say what is unclear. Never give doses.
Reply only as JSON: {"found": true|false, "brand": "...", "generic": "...", "strength": "...", "form": "...",
"unclear": "..."}"""
PHOTO_TYPES = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}


@router.post("/drugs/identify", dependencies=[limit_by_user("ai_medicine_photo", 30, 3600)])
async def identify(request: Request, file: UploadFile = File(...), user: dict = Depends(get_current_user),
                   db=Depends(get_db)):
    """Photo of a medicine pack -> its name, so the app can search for it."""
    mime = (file.content_type or "").lower()
    if mime == "image/jpg":
        mime = "image/jpeg"
    if mime not in PHOTO_TYPES:
        raise ApiError(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "unsupported_file", "Please use a JPG or PNG photo.")
    data = await file.read(8 * 1024 * 1024 + 1)
    if not data:
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "empty_file", "The photo is empty.")
    if len(data) > 8 * 1024 * 1024:
        raise ApiError(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "file_too_large", "The photo is larger than 8 MB.")
    try:
        res = await get_ai_service(request).generate(
            AIMedicinePhoto, PHOTO_SYSTEM, "Read the medicine name on this pack.",
            images=[(mime, base64.b64encode(data).decode())])
    except AIUnavailableError as exc:
        raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_unavailable", exc.message)
    d = res.data
    if not d.found or not (d.brand.strip() or d.generic.strip()):
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "not_readable",
                       d.unclear or "Could not read the medicine name. Take a clear photo of the name on the box.")
    brand = d.brand.strip()
    known = await db.medicine_brands.find_one({"brand_key": key(brand)}) if brand else None
    return {"brand": known["brand"] if known else brand, "generic": known["generic"] if known else d.generic.strip(),
            "strength": d.strength.strip(), "form": d.form.strip(), "in_list": bool(known),
            "search": (known["brand"] if known else brand) or d.generic.strip(), "ai_provider": res.provider}
