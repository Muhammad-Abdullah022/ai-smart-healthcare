"""Loads the sourced lab data (backend/data/labs/*.csv) into MongoDB.

Runs at startup; only re-imports when the CSV files change. Every row keeps its source URL
and the date it was checked. Nothing is invented: labs without a published price are stored
without a price, and cities without researched labs simply have none.
"""
import csv
import hashlib
import random
from datetime import datetime, timezone
from pathlib import Path

from app.labs.catalog import FAMILIES, family_of

DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "labs"
FILES = ("all_target_cities_tehsils.csv", "sourced_lab_records_starter.csv", "sourced_test_prices_starter.csv")
# Extra researched data, same columns (kept separate so each file's origin stays clear).
EXTRA_LAB_FILES = ("added_lab_records.csv", "phc_registered_labs.csv")
EXTRA_PRICE_FILES = ("added_test_prices.csv",)
# A price row with city "*" is a chain-wide published rate: it applies to that lab's branches in every city.
ALL_CITIES = "*"
# Demo prices (made up for the FYP demo). Stored separately, shown only when the user switches on
# "Demo prices", and always labelled "Demo price — not real".
DEMO_FILE = "demo_prices.csv"
# Bump when the demo generation below changes, so the data is re-imported.
LOADER_VERSION = b"labs-v3-demo-contacts-all-prices"

# ---- Demo data (made up, always flagged): contacts for labs with no published address/phone, and an
# estimated price for every lab x test that has no real published price. Deterministic (seeded by name),
# so the same lab always shows the same demo values.
BASE_PRICE = {  # typical private-lab price in PKR
    "hba1c": 1300, "dengue": 1400, "malaria": 500, "typhoid": 1100, "cbc": 850, "hb": 300, "tlc": 350,
    "dlc": 350, "esr": 400, "crp": 950, "sugar": 300, "lipid": 1900, "lft": 1600, "rft": 1500,
    "creatinine": 550, "uric_acid": 650, "thyroid": 1800, "urine": 400, "hcv": 1000, "hbv": 900, "hiv": 1200,
    "pregnancy": 1200, "vit_b12": 2800, "vit_d": 3000, "ferritin": 1900, "blood_group": 350, "ana": 2200,
    "aso": 900, "psa": 2200, "pt_inr": 950, "prolactin": 1700, "electrolytes": 1400, "ra_factor": 850,
    "urea": 500, "stool": 450, "platelets": 350, "tb": 900,
}
BIG_CHAINS = ("chughtai", "excel lab", "idc", "islamabad diagnostic", "shaukat khanum", "citilab", "citi lab",
              "dr. essa", "essa lab", "al-noor", "alnoor", "hormone lab", "lahore pcr")
AREA_CODE = {
    "lahore": "042", "faisalabad": "041", "rawalpindi": "051", "multan": "061", "gujranwala": "055",
    "sialkot": "052", "sahiwal": "040", "okara": "044", "sargodha": "048", "bahawalpur": "062",
    "rahim yar khan": "068", "dera ghazi khan": "064", "d.g. khan": "064", "jhang": "047", "chiniot": "047",
    "sheikhupura": "056", "nankana sahib": "056", "kasur": "049", "gujrat": "053", "jhelum": "0544",
    "attock": "057", "chakwal": "0543", "vehari": "067", "khanewal": "065", "pakpattan": "0457",
    "bahawalnagar": "063", "muzaffargarh": "066", "mianwali": "0459", "bhakkar": "0453", "layyah": "0606",
    "toba tek singh": "046", "hafizabad": "0547", "mandi bahauddin": "0546", "narowal": "0542",
    "khushab": "0454", "lodhran": "0608", "rajanpur": "0604",
}
ROADS = ("Main Bazar", "G.T. Road", "Railway Road", "College Road", "Jail Road", "Hospital Road", "Circular Road",
         "Club Road", "Canal Road", "Stadium Road", "Church Road", "Kutchery Road", "Grain Market Road", "Bank Road")
LANDMARKS = ("DHQ Hospital", "THQ Hospital", "Government College", "Jamia Masjid", "General Bus Stand",
             "Chowk Fawara", "City Police Station", "Ghalla Mandi", "Post Office", "Committee Bazar")


def _rng(*parts: str) -> random.Random:
    return random.Random(hashlib.sha256("|".join(parts).encode()).hexdigest())


def _missing(text: str) -> bool:
    t = (text or "").lower()
    return not t.strip() or "not listed" in t or "not stated" in t


def demo_address(lab_name: str, city: str) -> str:
    r = _rng("addr", lab_name, city)
    road = r.choice(ROADS)
    style = r.randrange(3)
    if style == 0:
        return f"Shop No. {r.randint(1, 40)}, {road}, {city}"
    if style == 1:
        return f"Near {r.choice(LANDMARKS)}, {road}, {city}"
    return f"{r.randint(1, 250)}-{r.choice('ABCDEFG')}, {road}, opposite {r.choice(LANDMARKS)}, {city}"


def demo_phone(lab_name: str, city: str, district: str) -> str:
    r = _rng("phone", lab_name, city)
    code = AREA_CODE.get(_key(district)) or AREA_CODE.get(_key(city))
    if code and r.random() < 0.5:
        digits = 10 - len(code) + 1  # Pakistani landlines: area code + local number = 11 digits with the 0
        return f"{code}-{r.randint(10 ** (digits - 1), 10 ** digits - 1)}"
    return f"03{r.choice(['00', '01', '02', '03', '05', '06', '08', '11', '13', '21', '33', '45'])}-{r.randint(1000000, 9999999)}"


def _tier(lab: dict) -> float:
    name, kind = lab["lab_name"].lower(), lab.get("lab_type", "").lower()
    if "government" in kind or "public" in kind or any(w in name for w in ("thq", "dhq", "govt", "government")):
        return 0.3
    if any(c in name for c in BIG_CHAINS):
        return 1.15
    return _rng("tier", lab["lab_name"], lab["city"]).uniform(0.7, 1.0)


def demo_price(lab: dict, family: str) -> float:
    r = _rng("price", lab["lab_name"], lab["city"], family)
    p = BASE_PRICE.get(family, 1000) * _tier(lab) * r.uniform(0.88, 1.12)
    step = 10 if p < 500 else 50
    return float(max(step, round(p / step) * step))


def _rows(name: str) -> list[dict]:
    with (DATA_DIR / name).open(encoding="utf-8-sig", newline="") as f:
        return [{k.strip(): (v or "").strip() for k, v in r.items()} for r in csv.DictReader(f)]


def _num(text: str) -> float | None:
    try:
        return float(text) if text else None
    except ValueError:
        return None


def _key(text: str) -> str:
    return " ".join(text.lower().split())


async def ensure_lab_data(db) -> None:
    if not all((DATA_DIR / f).exists() for f in FILES):
        return
    present = [f for f in FILES + EXTRA_LAB_FILES + EXTRA_PRICE_FILES + (DEMO_FILE,) if (DATA_DIR / f).exists()]
    digest = hashlib.sha256(LOADER_VERSION + b"".join((DATA_DIR / f).read_bytes() for f in present)).hexdigest()
    meta = await db.meta.find_one({"_id": "lab_data"})
    if meta and meta.get("sha256") == digest:
        return

    now = datetime.now(timezone.utc)
    locations = [{
        "division": r["division_as_provided"], "district": r["district_as_provided"],
        "city": r["city_or_tehsil_as_provided"], "city_key": _key(r["city_or_tehsil_as_provided"]),
        "coverage": r["coverage_status"],
    } for r in _rows(FILES[0])]

    labs = [{
        "district": r["district"], "city": r["city_or_tehsil"], "city_key": _key(r["city_or_tehsil"]),
        "lab_name": r["lab_name"], "lab_key": _key(r["lab_name"]), "branch": r["branch_name"],
        "address": r["address"], "phone": r["phone"], "lab_type": r["lab_type"],
        "price_status": r["price_status"], "source_url": r["source_url"], "source_type": r["source_type"],
        "checked": r["source_checked_date"], "data_status": r["data_status"],
    } for name in (FILES[1], *EXTRA_LAB_FILES) if (DATA_DIR / name).exists() for r in _rows(name)]
    for lab in labs:
        lab["address_demo"] = _missing(lab["address"])
        if lab["address_demo"]:
            lab["address"] = demo_address(lab["lab_name"], lab["city"])
        lab["phone_demo"] = not lab["phone"].strip()
        if lab["phone_demo"]:
            lab["phone"] = demo_phone(lab["lab_name"], lab["city"], lab["district"])

    prices = []
    price_rows = [r for name in (FILES[2], *EXTRA_PRICE_FILES) if (DATA_DIR / name).exists() for r in _rows(name)]
    for r in price_rows:
        try:
            price = float(r["price_pkr"]) if r["price_pkr"] else None
        except ValueError:
            price = None
        prices.append({
            "city_key": ALL_CITIES if r["city"].strip() == ALL_CITIES else _key(r["city"]), "lab_key": _key(r["lab_name"]), "lab_name": r["lab_name"],
            "test_name": r["test_name_as_published"], "family": family_of(r["test_name_as_published"]),
            "price_pkr": price, "discount_price_pkr": _num(r.get("discount_price_pkr", "")), "source_url": r["source_url"], "source_type": r["source_type"],
            "checked": r["source_checked_date"], "notes": r["notes"],
        })

    demo = [{
        "city_key": _key(r["city"]), "lab_key": _key(r["lab_name"]), "lab_name": r["lab_name"],
        "test_name": r["test_name"], "family": family_of(r["test_name"]), "price_pkr": _num(r["price_pkr"]),
        "category": r.get("category", ""),
    } for r in (_rows(DEMO_FILE) if (DATA_DIR / DEMO_FILE).exists() else [])]

    # Estimated (demo) price for every lab and test that has no real published price and no demo-file price.
    real = {(p["lab_key"], p["family"], p["city_key"]) for p in prices}
    covered = {(d["lab_key"], d["family"], d["city_key"]) for d in demo}
    for lab in labs:
        for fam, fam_name, _ in FAMILIES:
            if ((lab["lab_key"], fam, lab["city_key"]) in real or (lab["lab_key"], fam, ALL_CITIES) in real
                    or (lab["lab_key"], fam, lab["city_key"]) in covered):
                continue
            covered.add((lab["lab_key"], fam, lab["city_key"]))
            demo.append({"city_key": lab["city_key"], "lab_key": lab["lab_key"], "lab_name": lab["lab_name"],
                         "test_name": fam_name, "family": fam, "price_pkr": demo_price(lab, fam),
                         "category": "estimated"})

    for coll, docs in (("lab_locations", locations), ("labs", labs), ("lab_prices", prices),
                       ("lab_demo_prices", demo)):
        await db[coll].delete_many({})
        for i in range(0, len(docs), 5000):
            await db[coll].insert_many(docs[i:i + 5000], ordered=False)
    await db.meta.update_one({"_id": "lab_data"}, {"$set": {"sha256": digest, "imported_at": now,
                             "counts": {"locations": len(locations), "labs": len(labs), "prices": len(prices),
                                        "demo_prices": len(demo)}}},
                             upsert=True)
    print(f"[labs] imported {len(locations)} cities, {len(labs)} labs, {len(prices)} prices, "
          f"{len(demo)} demo prices")
