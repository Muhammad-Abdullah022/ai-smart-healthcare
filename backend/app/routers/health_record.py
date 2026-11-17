"""Health record & patient care: automatic health record (38/39), PDF + QR export (50),
future health risk with recommendations (40/45), health trends (41) and vitals incl. smartwatch (42)."""
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Literal

from bson import Binary
from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app.ai.lab_ranges import find_param, number
from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.core.security import verify_password
from app.deps import get_current_user, get_db
from app.health.record import VITAL_KINDS, age_of, build_record, latest_vitals
from app.health.risk import assess
from app.repositories.user_repository import to_object_id
from app.routers.consents import has_consent

router = APIRouter(tags=["health record"])
SHARE_HOURS = 24
VitalKind = Literal["bp", "sugar_fasting", "sugar_random", "weight", "heart_rate", "temperature", "spo2", "steps", "sleep"]
# Sensible limits so a typing mistake (e.g. 1200 heart rate) is rejected.
LIMITS = {"bp": (50, 260), "sugar_fasting": (20, 700), "sugar_random": (20, 900), "weight": (2, 350),
          "heart_rate": (25, 250), "temperature": (90, 110), "spo2": (50, 100), "steps": (0, 100000), "sleep": (0, 24)}


@router.get("/health-record")
async def health_record(user: dict = Depends(get_current_user), db=Depends(get_db)):
    return await build_record(db, user)


class PasswordIn(BaseModel):
    password: str = Field(min_length=1, max_length=128)


async def _locked_pdf(db, user: dict, password: str) -> bytes:
    try:  # imported here so the rest of the app runs even before the PDF packages are installed
        from app.health.pdf import build_pdf, lock_pdf
    except ImportError:
        raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "pdf_unavailable",
                       "PDF export needs new packages: close the backend window and run START_BACKEND.bat again.")
    if not verify_password(password, user["password_hash"]):
        raise ApiError(status.HTTP_403_FORBIDDEN, "wrong_password", "That is not your login password.")
    record = await build_record(db, user)
    risk = await _risk(db, user)
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "record.export", "details": {},
                                      "created_at": datetime.now(timezone.utc)})
    return lock_pdf(build_pdf(record, risk), password)


@router.post("/health-record/pdf", dependencies=[limit_by_user("record_pdf", 20, 3600)])
async def record_pdf(body: PasswordIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """The whole record as a PDF that opens only with the user's login password."""
    pdf = await _locked_pdf(db, user, body.password)
    return Response(pdf, media_type="application/pdf", headers={
        "Content-Disposition": 'attachment; filename="health-record.pdf"', "Cache-Control": "no-store"})


@router.post("/health-record/share", dependencies=[limit_by_user("record_share", 10, 3600)])
async def share_record(body: PasswordIn, request: Request, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """A link (shown as a QR code) to the locked PDF. It expires after 24 hours; the PDF still needs the password."""
    pdf = await _locked_pdf(db, user, body.password)
    token = secrets.token_urlsafe(24)
    expires = datetime.now(timezone.utc) + timedelta(hours=SHARE_HOURS)
    await db.record_shares.insert_one({"user_id": user["_id"], "token_hash": hashlib.sha256(token.encode()).hexdigest(),
                                       "pdf": Binary(pdf), "expires_at": expires, "created_at": datetime.now(timezone.utc)})
    base = (get_settings().public_base_url or str(request.base_url)).rstrip("/")
    return {"url": f"{base}/health-record/shared/{token}", "expires_at": expires.isoformat(), "hours": SHARE_HOURS}


@router.get("/health-record/shared/{token}", include_in_schema=False)
async def shared_pdf(token: str, db=Depends(get_db)):
    doc = await db.record_shares.find_one({"token_hash": hashlib.sha256(token.encode()).hexdigest()})
    exp = doc and doc["expires_at"]
    if exp and exp.tzinfo is None:
        exp = exp.replace(tzinfo=timezone.utc)
    if not doc or exp < datetime.now(timezone.utc):
        raise ApiError(status.HTTP_404_NOT_FOUND, "link_expired", "This link has expired or was turned off.")
    return Response(bytes(doc["pdf"]), media_type="application/pdf", headers={
        "Content-Disposition": 'inline; filename="health-record.pdf"', "Cache-Control": "no-store"})


@router.delete("/health-record/share", status_code=status.HTTP_204_NO_CONTENT)
async def stop_sharing(user: dict = Depends(get_current_user), db=Depends(get_db)):
    await db.record_shares.delete_many({"user_id": user["_id"]})


# ---------------- vitals (manual or smartwatch) ----------------
class VitalIn(BaseModel):
    kind: VitalKind
    value: float
    value2: float | None = Field(default=None, description="Diastolic for blood pressure")
    at: datetime | None = None
    source: Literal["manual", "watch"] = "manual"
    note: str = Field(default="", max_length=120)


def _vital_out(v: dict) -> dict:
    label, unit = VITAL_KINDS[v["kind"]]
    at = v["at"].replace(tzinfo=timezone.utc) if v["at"].tzinfo is None else v["at"]
    return {"id": str(v["_id"]), "kind": v["kind"], "label": label, "unit": unit, "value": v["value"],
            "value2": v.get("value2"), "at": at.isoformat(), "source": v.get("source", "manual"), "note": v.get("note", "")}


@router.post("/vitals", status_code=status.HTTP_201_CREATED)
async def add_vital(body: VitalIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    lo, hi = LIMITS[body.kind]
    if not lo <= body.value <= hi or (body.kind == "bp" and not (body.value2 and 30 <= body.value2 <= 160)):
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "out_of_range",
                       "That value looks wrong. Please check the reading." if body.kind != "bp"
                       else "Enter both numbers of the blood pressure, e.g. 120 / 80.")
    doc = {"user_id": user["_id"], **body.model_dump(exclude={"at"}), "at": body.at or datetime.now(timezone.utc)}
    doc["_id"] = (await db.vitals.insert_one(doc)).inserted_id
    return _vital_out(doc)


class VitalsBatch(BaseModel):
    readings: list[VitalIn] = Field(min_length=1, max_length=200)


@router.post("/vitals/batch", status_code=status.HTTP_201_CREATED)
async def add_vitals_batch(body: VitalsBatch, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Readings synced from a smartwatch (values outside the safe limits are skipped)."""
    docs = [{"user_id": user["_id"], **r.model_dump(exclude={"at"}), "at": r.at or datetime.now(timezone.utc)}
            for r in body.readings if LIMITS[r.kind][0] <= r.value <= LIMITS[r.kind][1]]
    if docs:
        await db.vitals.insert_many(docs)
    return {"saved": len(docs)}


@router.get("/vitals")
async def list_vitals(kind: VitalKind | None = None, days: int = Query(90, ge=1, le=730),
                      user: dict = Depends(get_current_user), db=Depends(get_db)):
    flt = {"user_id": user["_id"], "at": {"$gte": datetime.now(timezone.utc) - timedelta(days=days)}}
    if kind:
        flt["kind"] = kind
    return [_vital_out(v) async for v in db.vitals.find(flt).sort("at", -1).limit(1000)]


@router.delete("/vitals/{vital_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_vital(vital_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    oid = to_object_id(vital_id)
    res = await db.vitals.delete_one({"_id": oid, "user_id": user["_id"]}) if oid else None
    if not res or res.deleted_count == 0:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Reading not found.")


# ---------------- trends ----------------
def _stats(points: list[dict]) -> dict:
    vals = [p["value"] for p in points]
    first, last = vals[0], vals[-1]
    return {"count": len(vals), "latest": last, "min": min(vals), "max": max(vals),
            "average": round(sum(vals) / len(vals), 1), "change": round(last - first, 1),
            "direction": "up" if last > first * 1.03 else "down" if last < first * 0.97 else "steady"}


NORMAL = {"bp": (90, 129), "sugar_fasting": (70, 99), "sugar_random": (70, 139), "heart_rate": (60, 100),
          "temperature": (97, 99.5), "spo2": (95, 100), "sleep": (7, 9)}


@router.get("/health-trends")
async def health_trends(days: int = Query(90, ge=7, le=730), user: dict = Depends(get_current_user), db=Depends(get_db)):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    series: dict[str, list] = {}
    async for v in db.vitals.find({"user_id": user["_id"], "at": {"$gte": since}}).sort("at", 1):
        series.setdefault(v["kind"], []).append(v)
    vitals = []
    for kind, items in series.items():
        label, unit = VITAL_KINDS[kind]
        points = [{"at": (v["at"].replace(tzinfo=timezone.utc) if v["at"].tzinfo is None else v["at"]).isoformat(),
                   "value": v["value"], "value2": v.get("value2")} for v in items]
        st = _stats(points)
        lo, hi = NORMAL.get(kind, (None, None))
        st["in_normal_range"] = (lo is None) or (lo <= st["latest"] <= hi)
        vitals.append({"kind": kind, "label": label, "unit": unit, "points": points, "stats": st,
                       "normal": {"low": lo, "high": hi}})

    # Lab values that appear in two or more reports.
    labs: dict[str, dict] = {}
    async for r in db.medical_reports.find({"user_id": user["_id"]}).sort("created_at", 1):
        for v in (r.get("analysis") or {}).get("values", []):
            p, val = find_param(v.get("name", "")), number(v.get("value", ""))
            if p and val is not None:
                at = r["created_at"].replace(tzinfo=timezone.utc) if r["created_at"].tzinfo is None else r["created_at"]
                entry = labs.setdefault(p.key, {"name": p.key, "unit": v.get("unit", ""), "points": []})
                entry["points"].append({"at": at.isoformat(), "value": val, "flag": v.get("flag")})
    lab_trends = [{**e, "stats": _stats(e["points"])} for e in labs.values() if len(e["points"]) >= 2]

    # Medicine adherence per week.
    weeks: dict[str, dict] = {}
    async for log in db.medication_intake.find({"user_id": user["_id"], "day": {"$gte": since.date().isoformat()}}):
        d = datetime.fromisoformat(log["day"])
        wk = (d - timedelta(days=d.weekday())).date().isoformat()
        w = weeks.setdefault(wk, {"week": wk, "taken": 0, "missed": 0, "skipped": 0})
        if log.get("status") in w:
            w[log["status"]] += 1
    adherence = sorted(weeks.values(), key=lambda w: w["week"])
    for w in adherence:
        total = w["taken"] + w["missed"] + w["skipped"]
        w["percent"] = round(100 * w["taken"] / total) if total else None

    mood = []
    if await has_consent(db, user["_id"], "mental_health"):
        async for m in db.mood_entries.find({"user_id": user["_id"], "day": {"$gte": since.date().isoformat()}}).sort("day", 1):
            mood.append({"day": m["day"], "mood": m.get("mood"), "score": m.get("mood")})

    return {"days": days, "vitals": vitals, "labs": lab_trends, "adherence": adherence, "mood": mood}


# ---------------- risk & recommendations ----------------
class LifestyleIn(BaseModel):
    height_cm: float | None = Field(default=None, ge=80, le=230)
    weight_kg: float | None = Field(default=None, ge=20, le=350)
    waist_cm: float | None = Field(default=None, ge=40, le=200)
    smoker: bool | None = None
    activity: Literal["active", "some", "inactive"] | None = None
    diabetes_parents: Literal["none", "one", "both"] | None = None
    family_history: list[str] | None = Field(default=None, max_length=20)


async def _risk(db, user: dict) -> dict:
    profile = await db.profiles.find_one({"user_id": user["_id"]}) or {}
    vitals = await latest_vitals(db, user["_id"])
    reports = [r async for r in db.medical_reports.find({"user_id": user["_id"]}).sort("created_at", -1).limit(30)]
    out = assess(profile, age_of(profile.get("date_of_birth")), vitals, reports)
    out["lifestyle"] = profile.get("lifestyle") or {}
    return out


@router.get("/health-risk")
async def health_risk(user: dict = Depends(get_current_user), db=Depends(get_db)):
    return await _risk(db, user)


@router.put("/health-risk/lifestyle")
async def save_lifestyle(body: LifestyleIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    profile = await db.profiles.find_one({"user_id": user["_id"]}) or {}
    life = {**(profile.get("lifestyle") or {}), **body.model_dump(exclude_none=True)}
    await db.profiles.update_one({"user_id": user["_id"]}, {"$set": {"lifestyle": life}}, upsert=True)
    if body.weight_kg:
        await db.vitals.insert_one({"user_id": user["_id"], "kind": "weight", "value": body.weight_kg, "value2": None,
                                    "source": "manual", "note": "", "at": datetime.now(timezone.utc)})
    return await _risk(db, user)
