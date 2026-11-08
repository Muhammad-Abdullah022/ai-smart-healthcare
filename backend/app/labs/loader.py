"""Loads the sourced lab data (backend/data/labs/*.csv) into MongoDB.

Runs at startup; only re-imports when the CSV files change. Every row keeps its source URL
and the date it was checked. Nothing is invented: labs without a published price are stored
without a price, and cities without researched labs simply have none.
"""
import csv
import hashlib
from datetime import datetime, timezone
from pathlib import Path

from app.labs.catalog import family_of

DATA_DIR = Path(__file__).resolve().parents[2] / "data" / "labs"
FILES = ("all_target_cities_tehsils.csv", "sourced_lab_records_starter.csv", "sourced_test_prices_starter.csv")
# Extra researched data, same columns (kept separate so each file's origin stays clear).
EXTRA_LAB_FILES = ("added_lab_records.csv", "phc_registered_labs.csv")
EXTRA_PRICE_FILES = ("added_test_prices.csv",)
# A price row with city "*" is a chain-wide published rate: it applies to that lab's branches in every city.
ALL_CITIES = "*"


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
    present = [f for f in FILES + EXTRA_LAB_FILES + EXTRA_PRICE_FILES if (DATA_DIR / f).exists()]
    digest = hashlib.sha256(b"".join((DATA_DIR / f).read_bytes() for f in present)).hexdigest()
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

    for coll, docs in (("lab_locations", locations), ("labs", labs), ("lab_prices", prices)):
        await db[coll].delete_many({})
        if docs:
            await db[coll].insert_many(docs)
    await db.meta.update_one({"_id": "lab_data"}, {"$set": {"sha256": digest, "imported_at": now,
                             "counts": {"locations": len(locations), "labs": len(labs), "prices": len(prices)}}},
                             upsert=True)
    print(f"[labs] imported {len(locations)} cities, {len(labs)} labs, {len(prices)} prices")
