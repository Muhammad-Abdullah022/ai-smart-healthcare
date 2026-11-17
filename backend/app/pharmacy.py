"""Medicine reference data (brands -> salt) and the pharmacy directory.

data/medicines/generics.csv : one row per salt (generic): class, uses, common side effects, warnings.
data/medicines/brands.csv   : Pakistani brand names -> salt, company, forms, strengths (the app's list).
data/medicines/brands_drap_2021.csv : brands from DRAP's 2021 maximum retail price list (Open Data Pakistan).
data/pharmacies/sourced_pharmacies.csv : real pharmacies found online (with the source page).
Every supported city also gets its government hospital pharmacy (DHQ for a district city, THQ for a tehsil)
and a few demo pharmacies (made up, flagged demo=True, shown with a "demo" label).

Data is imported into MongoDB at start-up when the files change (same pattern as labs and doctors).
"""
import csv
import hashlib
import random
import re
from datetime import datetime, timezone
from pathlib import Path

from app.labs.loader import demo_address, demo_phone

DATA = Path(__file__).resolve().parents[1] / "data"
MED_DIR = DATA / "medicines"
PHARM_DIR = DATA / "pharmacies"
CITIES_FILE = DATA / "labs" / "all_target_cities_tehsils.csv"
VERSION = b"pharmacy-v2"
BIG_CITIES = {"Lahore", "Faisalabad", "Rawalpindi", "Multan", "Gujranwala", "Sialkot", "Bahawalpur", "Sargodha",
              "Sahiwal", "Sheikhupura"}
DEMO_NAMES = ["Madina Medical Store", "Al-Shifa Pharmacy", "Rehman Medicos", "City Pharmacy", "Al-Noor Medical Store",
              "Fazal Medical Hall", "New Life Pharmacy", "Ittefaq Medical Store", "Care Plus Pharmacy",
              "Khan Medicos", "Bismillah Medical Store", "Health Point Pharmacy", "Imran Medical Store",
              "Faisal Medicos", "Hamza Pharmacy", "Ali Medical Store"]


def key(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (text or "").lower()).strip()


def _rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        return [{k.strip(): (v or "").strip() for k, v in r.items() if k} for r in csv.DictReader(f)]


def _split(text: str) -> list[str]:
    return [p.strip() for p in (text or "").split(";") if p.strip()]


def _cities() -> list[tuple[str, str]]:
    out = []
    for r in _rows(CITIES_FILE):
        city, district = r.get("city_or_tehsil_as_provided", ""), r.get("district_as_provided", "")
        if city:
            out.append((city, district or city))
    return out


def build_pharmacies() -> list[dict]:
    pharmacies = []
    for r in _rows(PHARM_DIR / "sourced_pharmacies.csv"):
        pharmacies.append({"city": r["city"], "name": r["name"], "address": r["address"], "phone": r["phone"],
                           "hours": r.get("hours", ""), "kind": r.get("kind", "independent"),
                           "source": r.get("source", ""), "demo": False})
    for city, district in _cities():
        is_district = key(city) == key(district)
        hosp = "DHQ" if is_district else "THQ"
        pharmacies.append({
            "city": city, "name": f"{hosp} Hospital Pharmacy, {city}", "address": f"{hosp} Hospital, {city}",
            "phone": "", "hours": "24 hours (emergency)", "kind": "government",
            "source": "Punjab government hospital — free medicines for registered patients; confirm locally",
            "demo": False,
        })
        r = random.Random(hashlib.sha256(f"pharm|{city}".encode()).hexdigest())
        count = 5 if city in BIG_CITIES else (3 if is_district else 2)
        for name in r.sample(DEMO_NAMES, count):
            pharmacies.append({
                "city": city, "name": name, "address": demo_address(name, city),
                "phone": demo_phone(name, city, district),
                "hours": r.choice(["24 hours", "9 am – 11 pm", "8 am – 12 am", "10 am – 10 pm"]),
                "kind": "independent", "source": "", "demo": True,
            })
    for p in pharmacies:
        p["city_key"] = key(p["city"])
        p["name_key"] = key(p["name"])
        p["open_24h"] = "24" in p["hours"]
    return pharmacies


def build_medicines() -> tuple[list[dict], list[dict]]:
    generics = []
    for r in _rows(MED_DIR / "generics.csv"):
        generics.append({"generic": r["generic"], "generic_key": key(r["generic"]), "drug_class": r["drug_class"],
                         "uses": r["uses"], "side_effects": r["common_side_effects"], "warnings": r["warnings"]})
    brands: dict[str, dict] = {}
    # brands.csv = the app's checked list; brands_*.csv = official lists (e.g. DRAP MRP list 2021), which win.
    for path in sorted(MED_DIR.glob("brands*.csv"), key=lambda p: p.name != "brands.csv"):
        for r in _rows(path):
            brands[key(r["brand"])] = {
                "brand": r["brand"], "brand_key": key(r["brand"]), "generic": r["generic"],
                "generic_key": key(r["generic"]), "company": r.get("company", ""),
                "forms": _split(r["forms"]), "strengths": _split(r["strengths"]),
                "source": r.get("source", "") or "App medicine list"}
    return generics, list(brands.values())


async def ensure_pharmacy_data(db) -> None:
    files = sorted([*MED_DIR.glob("*.csv"), *PHARM_DIR.glob("*.csv"), CITIES_FILE])
    digest = hashlib.sha256(VERSION + b"".join(f.read_bytes() for f in files if f.exists())).hexdigest()
    meta = await db.meta.find_one({"_id": "pharmacy_data"})
    if meta and meta.get("sha256") == digest:
        return
    generics, brands = build_medicines()
    pharmacies = build_pharmacies()
    for coll, docs in (("medicine_generics", generics), ("medicine_brands", brands), ("pharmacies", pharmacies)):
        await db[coll].delete_many({})
        if docs:
            await db[coll].insert_many(docs, ordered=False)
    await db.meta.update_one({"_id": "pharmacy_data"}, {"$set": {
        "sha256": digest, "generics": len(generics), "brands": len(brands), "pharmacies": len(pharmacies),
        "loaded_at": datetime.now(timezone.utc)}}, upsert=True)
