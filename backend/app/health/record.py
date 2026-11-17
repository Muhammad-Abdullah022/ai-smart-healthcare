"""The user's health record, built automatically from everything saved in the app.

Nothing is typed twice: symptom checks (chatbot), report readings, prescriptions, medicines and their
intake, vitals (manual or smartwatch), mental-health screenings (only with consent) and anything the user
added by hand to their medical history all appear here, newest first.
"""
import re
from datetime import date, datetime, timedelta, timezone

from app.routers.consents import has_consent

VITAL_KINDS = {
    "bp": ("Blood pressure", "mmHg"),
    "sugar_fasting": ("Fasting blood sugar", "mg/dL"),
    "sugar_random": ("Random blood sugar", "mg/dL"),
    "weight": ("Weight", "kg"),
    "heart_rate": ("Heart rate", "bpm"),
    "temperature": ("Temperature", "°F"),
    "spo2": ("Oxygen (SpO2)", "%"),
    "steps": ("Steps", "steps"),
    "sleep": ("Sleep", "hours"),
}


def _slug(text: str) -> str:
    return re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", (text or "").strip().lower()))


def doctor_websites(city: str, specialty: str) -> list[dict]:
    """Doctor search pages (Marham / oladoc) for the city and specialist the AI recommended."""
    c, sp = _slug(city) or "lahore", _slug(specialty) or "general-physician"
    return [{"site": "Marham", "url": f"https://www.marham.pk/doctors/{c}/{sp}"},
            {"site": "oladoc", "url": f"https://oladoc.com/pakistan/{c}/{sp}"}]


def age_of(dob) -> int | None:
    if not dob:
        return None
    if isinstance(dob, str):
        try:
            dob = date.fromisoformat(dob[:10])
        except ValueError:
            return None
    if isinstance(dob, datetime):
        dob = dob.date()
    today = date.today()
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


def _iso(d) -> str:
    return d.isoformat() if isinstance(d, (datetime, date)) else str(d or "")


async def latest_vitals(db, user_id) -> dict:
    out = {}
    async for v in db.vitals.find({"user_id": user_id}).sort("at", -1).limit(400):
        out.setdefault(v["kind"], v)
    return out


async def build_record(db, user: dict) -> dict:
    uid = user["_id"]
    profile = await db.profiles.find_one({"user_id": uid}) or {}
    lifestyle = profile.get("lifestyle") or {}

    city = profile.get("city") or ""
    checks = []
    otc_seen: dict[str, dict] = {}
    doctors_seen: dict[str, dict] = {}
    async for a in db.symptom_assessments.find({"user_id": uid}).sort("created_at", -1).limit(50):
        otc = [{"name": o.get("name", ""), "helps_with": o.get("helps_with", ""), "avoid_if": o.get("avoid_if", "")}
               for o in (a.get("otc_options") or []) if o.get("name")]
        spec = "" if str(a.get("specialist_type", "")).lower() in ("", "none", "null") else a["specialist_type"]
        for o in otc:
            otc_seen.setdefault(o["name"].lower(), {**o, "date": _iso(a["created_at"]),
                                                    "for_symptoms": a.get("symptoms", "")[:80]})
        if spec:
            doctors_seen.setdefault(spec.lower(), {"specialist": spec, "date": _iso(a["created_at"]),
                                                   "for_symptoms": a.get("symptoms", "")[:80],
                                                   "websites": doctor_websites(city, spec)})
        checks.append({
            "otc_options": otc, "doctor_websites": doctor_websites(city, spec) if spec else [],
            "date": _iso(a["created_at"]), "symptoms": a.get("symptoms", ""),
            "urgency": a.get("triage_level", ""),
            "possible_causes": [c.get("name", "") for c in (a.get("possible_causes") or [])][:4],
            "specialist": spec,
            "next_steps": (a.get("next_steps") or [])[:4],
            "tests": (a.get("tests_to_discuss") or [])[:5],
        })

    reports = []
    async for r in db.medical_reports.find({"user_id": uid}).sort("created_at", -1).limit(50):
        an = r.get("analysis") or {}
        reports.append({
            "id": str(r["_id"]), "date": _iso(r["created_at"]), "type": an.get("report_type", r.get("file_name", "")),
            "summary": an.get("summary", ""), "urgency": an.get("urgency", ""),
            "abnormal": [{"name": v.get("name"), "value": v.get("value"), "unit": v.get("unit", ""),
                          "flag": v.get("flag"), "critical": v.get("critical", False)}
                         for v in an.get("values", []) if v.get("flag") in ("low", "high")][:12],
        })

    medicines = []
    async for m in db.medicine_records.find({"user_id": uid}).sort("created_at", -1).limit(100):
        medicines.append({"name": m["name"], "salt": m.get("salt", ""), "strength": m.get("strength", ""),
                          "times": m.get("times", []), "instructions": m.get("instructions", ""),
                          "active": m.get("active", True), "start": m.get("start_date"), "end": m.get("end_date"),
                          "from_prescription": bool(m.get("prescription_id"))})

    prescriptions = []
    async for p in db.prescriptions.find({"user_id": uid, "status": "verified"}).sort("created_at", -1).limit(30):
        rd = p.get("reading") or {}
        prescriptions.append({"date": _iso(p["created_at"]), "doctor": rd.get("doctor_name", ""),
                              "notes": rd.get("notes", [])[:4],
                              "medicines": [f"{m.get('name', '')} {m.get('strength', '')} — {m.get('how_to_take', '')}".strip()
                                            for m in p.get("confirmed_medicines", [])]})

    since = (date.today() - timedelta(days=30)).isoformat()
    adherence = {"taken": 0, "skipped": 0, "missed": 0}
    async for log in db.medication_intake.find({"user_id": uid, "day": {"$gte": since}}):
        if log.get("status") in adherence:
            adherence[log["status"]] += 1

    history = []
    async for e in db.feature_entries.find({"user_id": uid, "feature": {"$in": [38, 39]}, "archived": False}).sort("created_at", -1):
        d = e["data"]
        history.append({"kind": d.get("kind") or d.get("record_type") or "Record", "name": d.get("name") or d.get("title", ""),
                        "year": d.get("year") or d.get("date") or "", "notes": d.get("notes", "")})

    vitals = {k: {"label": VITAL_KINDS[k][0], "unit": VITAL_KINDS[k][1], "value": v["value"],
                  "value2": v.get("value2"), "at": _iso(v["at"]), "source": v.get("source", "manual")}
              for k, v in (await latest_vitals(db, uid)).items() if k in VITAL_KINDS}

    mental = []
    if await has_consent(db, uid, "mental_health"):
        async for s in db.mental_assessments.find({"user_id": uid}).sort("created_at", -1).limit(5):
            mental.append({"date": _iso(s["created_at"]), "test": s["instrument"].upper(), "score": s["score"],
                           "severity": s["severity"]})

    appointments = []
    async for a in db.appointments.find({"user_id": uid}).sort("created_at", -1).limit(10):
        appointments.append({"date": _iso(a.get("preferred_date") or a["created_at"]), "doctor": a.get("doctor_name", ""),
                             "specialty": a.get("specialty", ""), "status": a.get("status", "")})

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "patient": {"name": profile.get("full_name") or user.get("full_name", ""), "email": user.get("email", ""),
                    "age": age_of(profile.get("date_of_birth")), "gender": profile.get("gender"),
                    "blood_group": profile.get("blood_group", "Unknown"), "city": profile.get("city"),
                    "allergies": profile.get("allergies", []), "conditions": profile.get("conditions", []),
                    "height_cm": lifestyle.get("height_cm"),
                    "emergency_contacts": profile.get("emergency_contacts", [])},
        "vitals": vitals, "symptom_checks": checks,
        "ai_medicines": list(otc_seen.values()), "recommended_doctors": list(doctors_seen.values()), "reports": reports, "medicines": medicines,
        "prescriptions": prescriptions, "adherence_30d": adherence, "history": history,
        "mental_health": mental, "appointments": appointments,
        "counts": {"symptom_checks": len(checks), "reports": len(reports), "medicines": len(medicines),
                   "prescriptions": len(prescriptions), "history": len(history),
                   "ai_medicines": len(otc_seen), "recommended_doctors": len(doctors_seen)},
    }
