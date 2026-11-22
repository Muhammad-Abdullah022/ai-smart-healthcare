"""Official medicine prices (feature 29: price comparison).

Source: DRAP maximum retail price (MRP) list 2021, published on Open Data Pakistan
("Pharmaceutical Prices in Pakistan 2021", 462 packs). The MRP is the same in every city in Pakistan.
DRAP has revised prices since 2021, so the app always says "2021 official price — today's price may be
higher, confirm at the pharmacy". Nothing here is made up: a pack without a price in the list shows no price.

The CSV is downloaded once by the backend (the laptop has internet) and kept at
data/medicines/drap_prices_2021.csv, then imported into MongoDB (collection medicine_prices).
"""
import csv
import hashlib
import io
import re
from datetime import datetime, timezone
from pathlib import Path

import httpx

from app.pharmacy import key

PRICE_FILE = Path(__file__).resolve().parents[1] / "data" / "medicines" / "drap_prices_2021.csv"
SOURCE_URL = ("https://opendata.com.pk/dataset/5738f0e7-940b-4a33-afdf-daf3d10782f1/resource/"
              "f3473d94-6814-46d1-a07c-fb40d60bbb9a/download/pharmaceutical-prices-in-pakistan-2021.csv")
SOURCE_PAGE = "https://opendata.com.pk/dataset/pharmaceutical-prices-in-pakistan-2021"
SOURCE_NAME = "DRAP maximum retail price list 2021 (Open Data Pakistan)"
VERSION = b"prices-v1"

_STRENGTH = re.compile(r"(\d+(?:\.\d+)?)\s*(mg|mcg|µg|g|gm|iu|ml|%)\b", re.I)
_PACK = re.compile(r"(?:(\d+)\s*[x×]\s*)?(\d+)\s*(?:'|`|’)?\s*s?\b", re.I)


def fix_text(text: str) -> str:
    """The published file has broken characters (UTF-8 read as Windows-1252); repair and tidy them."""
    t = text or ""
    if "â" in t or "Ã" in t:
        try:
            t = t.encode("cp1252", errors="ignore").decode("utf-8", errors="ignore")
        except UnicodeError:
            pass
    t = t.replace("…", " ").replace("’", "'").replace("`", "'")
    t = re.sub(r"\.{2,}|-{3,}", " ", t)
    t = re.sub(r"(^|\s)\.(?=\d)", r"\1", t)  # "Metronidazole .400mg" -> "Metronidazole 400mg"
    return re.sub(r"\s+", " ", t).strip(" ,;")


def price_value(text: str) -> float | None:
    m = re.search(r"(\d[\d,]*(?:\.\d+)?)", text or "")
    if not m:
        return None
    try:
        v = float(m.group(1).replace(",", ""))
    except ValueError:
        return None
    return v if v > 0 else None


def strengths(text: str) -> list[str]:
    """'Paracetamol 500mg & Caffeine 65mg' -> ['500 mg', '65 mg']"""
    out = []
    for num, unit in _STRENGTH.findall(text or ""):
        n = num.rstrip("0").rstrip(".") if "." in num else num
        s = f"{n} {unit.lower().replace('gm', 'g').replace('µg', 'mcg')}"
        if s not in out:
            out.append(s)
    return out


def pack_units(pack: str) -> int | None:
    """Tablets/capsules in a pack: "2x10's" -> 20, "30's" -> 30. Liquids/creams (ml, g) -> None."""
    p = (pack or "").lower()
    if re.search(r"\d\s*(ml|g|gm|doses?)\b", p):
        return None
    m = _PACK.search(p)
    if not m:
        return None
    a, b = m.group(1), m.group(2)
    n = int(a) * int(b) if a else int(b)
    return n if 0 < n <= 2000 else None


def form_of(name: str, formulation: str) -> str:
    t = f"{name} {formulation}".lower()
    for word, form in (("tab", "tablet"), ("caplet", "tablet"), ("cap", "capsule"), ("syrup", "syrup"),
                       ("susp", "syrup"), ("liquid", "syrup"), ("drop", "drops"), ("inj", "injection"),
                       ("infusion", "injection"), ("iv", "injection"), ("vial", "injection"), ("cream", "cream"),
                       ("gel", "cream"), ("ointment", "cream"), ("lotion", "cream"), ("inhaler", "inhaler"),
                       ("evohaler", "inhaler"), ("sachet", "sachet"), ("ors", "sachet")):
        if re.search(rf"\b{word}", t):
            return form
    return "other"


def parse(text: str) -> list[dict]:
    rows = []
    for r in csv.DictReader(io.StringIO(text.lstrip("﻿"))):
        brand = fix_text(r.get("Brand Name", ""))
        if not brand:
            continue
        formulation = fix_text(r.get("Formulation", ""))
        pack = fix_text(r.get("Pack Size", ""))
        mrp = price_value(r.get("MRP", ""))
        units = pack_units(pack)
        rows.append({
            "brand": brand, "brand_key": key(brand), "company": fix_text(r.get("Company Name", "")).rstrip(","),
            "formulation": formulation, "formulation_key": key(formulation), "pack": pack,
            "mrp": mrp, "units": units, "per_unit": round(mrp / units, 2) if mrp and units else None,
            "strengths": strengths(f"{brand} {formulation}"), "form": form_of(brand, formulation),
            "reg_no": str(r.get("reg_no", "")).strip(),
        })
    return rows


async def _download() -> str | None:
    try:
        async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
            res = await client.get(SOURCE_URL)
            res.raise_for_status()
            text = res.content.decode("utf-8-sig", errors="replace")
    except Exception as exc:  # no internet / site down: try again at the next start
        print(f"[prices] could not download the DRAP price list: {exc!r}")
        return None
    if "Brand Name" not in text[:400]:
        print("[prices] the downloaded file does not look like the price list")
        return None
    PRICE_FILE.write_text(text, encoding="utf-8")
    return text


async def ensure_price_data(db) -> None:
    if PRICE_FILE.exists():
        text = PRICE_FILE.read_text(encoding="utf-8")
    else:
        text = await _download()
        if text is None:
            return
    digest = hashlib.sha256(VERSION + text.encode()).hexdigest()
    meta = await db.meta.find_one({"_id": "price_data"})
    if meta and meta.get("sha256") == digest:
        return
    rows = parse(text)
    await db.medicine_prices.delete_many({})
    if rows:
        await db.medicine_prices.insert_many(rows, ordered=False)
    await db.meta.update_one({"_id": "price_data"}, {"$set": {
        "sha256": digest, "rows": len(rows), "loaded_at": datetime.now(timezone.utc)}}, upsert=True)
