"""Doctor directory (feature 10): loads data/doctors/*.csv into MongoDB and maps
AI specialist names (e.g. "General physician") to directory specialties."""
import csv
import hashlib
import re
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "doctors"

# Directory specialty -> words the AI or the user may use for it.
SPECIALTIES: dict[str, list[str]] = {
    "General Physician": ["general physician", "gp", "family", "medical specialist", "internal medicine", "physician",
                          "general practitioner", "medical officer"],
    "Cardiologist": ["cardio", "heart"],
    "Dermatologist": ["derma", "skin"],
    "ENT Specialist": ["ent", "ear", "nose", "throat", "otolaryng", "sinus", "tonsil"],
    "Gastroenterologist": ["gastro", "stomach", "liver", "hepatolog"],
    "Gynecologist": ["gyn", "obstetric", "women", "gynaec"],
    "Neurosurgeon": ["neurosurg"],
    "Neurologist": ["neuro", "brain", "headache"],
    "Orthopedic Surgeon": ["ortho", "bone", "joint", "fracture"],
    "Pediatrician": ["pediatric", "paediatric", "child"],
    "Psychiatrist": ["psychiatr", "mental health"],
    "Psychologist": ["psycholog", "counsel", "therap"],
    "Pulmonologist": ["pulmo", "chest", "lung", "respiratory"],
    "Urologist": ["urolog", "kidney stone", "bladder"],
    "Nephrologist": ["nephro", "kidney"],
    "Endocrinologist": ["endocrin", "diabetolog", "diabetes specialist", "thyroid", "hormone"],
    "Eye Specialist": ["eye", "ophthalm"],
    "Dentist": ["dent", "teeth", "tooth"],
    "General Surgeon": ["surgeon", "surgery"],
    "Oncologist": ["onco", "cancer"],
    "Rheumatologist": ["rheumat", "arthritis"],
}


def specialties_for(text: str | None) -> list[str]:
    """All directory specialties named in a doctor-type text, in the order they appear.

    The AI often answers "Pulmonologist (chest specialist) / General physician": the first one named is the
    main specialist. Words must start at a word boundary ("ent" must not match "gastroenterologist" or
    "dentist"). General Physician is only used when no specialist is named.
    """
    if not text:
        return []
    low = text.lower()
    for name in SPECIALTIES:
        if name.lower() == low.strip():
            return [name]
    found: list[tuple[int, str]] = []
    for name, words in SPECIALTIES.items():
        # Short words ("ent", "gp", "ear", "eye") must be whole words; longer ones may be word starts.
        positions = [m.start() for w in [name.lower(), *words]
                     for m in [re.search(r"(?<![a-z])" + re.escape(w) + (r"(?![a-z])" if len(w) <= 3 else ""), low)]
                     if m]
        if positions:
            found.append((min(positions), name))
    found.sort()
    names = [n for _, n in found]
    # "Neurosurgeon" also contains "neuro"/"surgeon": keep the most specific one only.
    if "Neurosurgeon" in names:
        names = [n for n in names if n not in ("Neurologist", "General Surgeon")]
    # Prefer a named specialist over a general physician, but keep GP as the backup.
    specific = [n for n in names if n != "General Physician"]
    return specific + (["General Physician"] if "General Physician" in names else [])


def normalize_specialty(text: str | None) -> str | None:
    if not text:
        return None
    names = specialties_for(text)
    return names[0] if names else text.strip().title()


def _key(text: str) -> str:
    return " ".join(text.lower().split())


async def ensure_doctor_data(db) -> None:
    files = sorted(DATA_DIR.glob("*.csv")) if DATA_DIR.exists() else []
    digest = hashlib.sha256(b"".join(f.name.encode() + f.read_bytes() for f in files)).hexdigest()
    meta = await db.meta.find_one({"_id": "doctor_data"})
    if meta and meta.get("sha256") == digest:
        return
    docs = []
    for f in files:
        with f.open(encoding="utf-8-sig", newline="") as fh:
            for r in csv.DictReader(fh):
                r = {k.strip().lower(): (v or "").strip() for k, v in r.items() if k}
                if not r.get("doctor_name") or not r.get("city"):
                    continue
                fee = re.sub(r"[^\d.]", "", r.get("fee_pkr", ""))
                docs.append({
                    "city": r["city"], "city_key": _key(r["city"]), "name": r["doctor_name"],
                    "specialty": normalize_specialty(r.get("specialty")) or "General Physician",
                    "qualification": r.get("qualification", ""), "clinic": r.get("clinic_name", ""),
                    "address": r.get("address", ""), "fee_pkr": float(fee) if fee else None,
                    "phone": r.get("phone", ""), "email": r.get("email", "").lower(),
                    "timings": r.get("timings", ""), "source_url": r.get("source_url", ""),
                    "checked": r.get("checked_date", ""), "file": f.name,
                    "experience_years": int(r["experience_years"]) if r.get("experience_years", "").isdigit() else None,
                    "gender": r.get("gender", ""), "about": r.get("about", ""),
                    # Made-up profile for the demo (demo_doctors.csv); the app labels it "Demo profile".
                    "demo": r.get("demo", "").lower() in ("yes", "true", "1"),
                })
    # Keep doctors who joined through the app (they have a login); only replace the imported lists.
    await db.doctors.delete_many({"user_id": {"$exists": False}})
    if docs:
        await db.doctors.insert_many(docs)
    await db.meta.update_one({"_id": "doctor_data"}, {"$set": {"sha256": digest, "count": len(docs),
                             "imported_at": datetime.now(timezone.utc)}}, upsert=True)
    print(f"[doctors] imported {len(docs)} doctors from {len(files)} file(s)")
