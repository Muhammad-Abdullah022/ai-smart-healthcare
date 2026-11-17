"""Medicines: manual entry & schedule (35), allergy warning (32), intake tracking & missed doses (36).

Safety rules:
  * The app never suggests doses. It only stores what the user (or their doctor's
    prescription) says.
  * Before saving, the medicine name/salt is compared with the user's recorded
    allergies. On a match the user must explicitly confirm. This is a simple
    name match (it will NOT catch every related drug) and that limitation is
    shown to the user.
"""
import re
from datetime import date, datetime, time, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field, field_validator

from app.core.errors import ApiError
from app.deps import get_current_user, get_db
from app.repositories.user_repository import to_object_id
from app.routers.notifications import notify

router = APIRouter(prefix="/medicines", tags=["medicines"])

MISSED_AFTER_MINUTES = 60
Form = Literal["tablet", "capsule", "syrup", "injection", "drops", "inhaler", "cream", "other"]
_TIME = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")

ALLERGY_LIMITATION = ("This check only compares names with the allergies saved in your profile. It does not know "
                      "every related medicine. Always ask your doctor or pharmacist.")


class MedicineIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    salt: str = Field(default="", max_length=120, description="Active ingredient, e.g. Paracetamol")
    strength: str = Field(default="", max_length=40, description='As written on the pack, e.g. "500 mg"')
    form: Form = "tablet"
    times: list[str] = Field(min_length=1, max_length=6, description='Daily times, "HH:MM" 24-hour')
    instructions: str = Field(default="", max_length=200, description='e.g. "after food"')
    start_date: date | None = None
    end_date: date | None = None
    confirm_allergy_override: bool = False
    # Set when the schedule comes from a prescription the user has verified (feature 34).
    prescription_id: str | None = None

    @field_validator("times")
    @classmethod
    def valid_times(cls, value: list[str]) -> list[str]:
        for t in value:
            if not _TIME.match(t):
                raise ValueError(f'"{t}" is not a valid time (use HH:MM, e.g. 08:00)')
        return sorted(set(value))


class MedicineOut(BaseModel):
    id: str
    name: str
    salt: str
    strength: str
    form: str
    times: list[str]
    instructions: str
    start_date: date | None
    end_date: date | None
    active: bool
    allergy_warning: str | None = None


class DoseOut(BaseModel):
    medicine_id: str
    name: str
    strength: str
    time: str
    status: Literal["taken", "skipped", "missed", "due", "upcoming"]


class IntakeIn(BaseModel):
    time: str
    status: Literal["taken", "skipped"]
    day: date | None = None

    @field_validator("time")
    @classmethod
    def valid_time(cls, value: str) -> str:
        if not _TIME.match(value):
            raise ValueError("time must be HH:MM")
        return value


def _local_now(tz_offset_minutes: int) -> datetime:
    """The app sends its UTC offset (Pakistan = +300) so 'today' means the user's today."""
    return datetime.now(timezone.utc) + timedelta(minutes=tz_offset_minutes)


def _words(text: str) -> set[str]:
    return {w for w in re.split(r"[^a-z0-9]+", text.lower()) if len(w) >= 3}


def allergy_match(allergies: list[str], name: str, salt: str) -> str | None:
    """Return the allergy that matches this medicine's name or salt, if any."""
    med_words = _words(f"{name} {salt}")
    for allergy in allergies:
        allergy_words = _words(allergy)
        if allergy_words and allergy_words <= med_words:
            return allergy
        # also catch e.g. allergy "penicillin" vs salt "amoxicillin/penicillin V"
        if any(a in w or w in a for a in allergy_words for w in med_words if len(w) >= 5 and len(a) >= 5):
            return allergy
    return None


def _out(doc: dict, warning: str | None = None) -> MedicineOut:
    return MedicineOut(id=str(doc["_id"]), name=doc["name"], salt=doc["salt"], strength=doc["strength"],
                       form=doc["form"], times=doc["times"], instructions=doc["instructions"],
                       start_date=doc.get("start_date"), end_date=doc.get("end_date"), active=doc["active"],
                       allergy_warning=warning or doc.get("allergy_warning"))


async def _owned(db, user, medicine_id: str) -> dict:
    oid = to_object_id(medicine_id)
    doc = await db.medicine_records.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
    if doc is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Medicine not found.")
    return doc


async def _check_allergy(db, user, body: MedicineIn) -> str | None:
    profile = await db.profiles.find_one({"user_id": user["_id"]}) or {}
    match = allergy_match(profile.get("allergies", []), body.name, body.salt)
    if match and not body.confirm_allergy_override:
        raise ApiError(status.HTTP_409_CONFLICT, "allergy_warning",
                       f'Warning: "{body.name}" may match your recorded allergy "{match}". '
                       f"Please check with your doctor or pharmacist before taking it. {ALLERGY_LIMITATION}")
    return f'Possible allergy match: "{match}" (you confirmed you want to save it)' if match else None


def _fields(body: MedicineIn) -> dict:
    data = body.model_dump(exclude={"confirm_allergy_override"}, mode="json")
    data["name"] = data["name"].strip()
    return data


@router.post("", response_model=MedicineOut, status_code=status.HTTP_201_CREATED)
async def add_medicine(body: MedicineIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    if body.prescription_id:
        oid = to_object_id(body.prescription_id)
        rx = await db.prescriptions.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
        if rx is None or rx.get("status") != "verified":
            raise ApiError(status.HTTP_409_CONFLICT, "prescription_not_verified",
                           "Please check and confirm the prescription before creating reminders from it.")
    warning = await _check_allergy(db, user, body)
    doc = {"user_id": user["_id"], **_fields(body), "active": True, "allergy_warning": warning,
           "created_at": datetime.now(timezone.utc)}
    doc["_id"] = (await db.medicine_records.insert_one(doc)).inserted_id
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "medicine.add",
                                      "details": {"allergy_override": bool(warning)},
                                      "created_at": doc["created_at"]})
    return _out(doc)


@router.get("", response_model=list[MedicineOut])
async def list_medicines(include_stopped: bool = False, user: dict = Depends(get_current_user), db=Depends(get_db)):
    query = {"user_id": user["_id"]} if include_stopped else {"user_id": user["_id"], "active": True}
    return [_out(d) async for d in db.medicine_records.find(query).sort("name", 1)]


@router.put("/{medicine_id}", response_model=MedicineOut)
async def update_medicine(medicine_id: str, body: MedicineIn, user: dict = Depends(get_current_user),
                          db=Depends(get_db)):
    doc = await _owned(db, user, medicine_id)
    warning = await _check_allergy(db, user, body)
    changes = {**_fields(body), "allergy_warning": warning}
    await db.medicine_records.update_one({"_id": doc["_id"]}, {"$set": changes})
    return _out({**doc, **changes})


@router.post("/{medicine_id}/stop", response_model=MedicineOut)
async def stop_medicine(medicine_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Stopping keeps the history (no hard delete of health records)."""
    doc = await _owned(db, user, medicine_id)
    await db.medicine_records.update_one({"_id": doc["_id"]}, {"$set": {"active": False}})
    return _out({**doc, "active": False})


def _active_on(doc: dict, day: date) -> bool:
    start = doc.get("start_date")
    end = doc.get("end_date")
    start = date.fromisoformat(start) if isinstance(start, str) else start
    end = date.fromisoformat(end) if isinstance(end, str) else end
    return doc["active"] and (start is None or start <= day) and (end is None or day <= end)


@router.get("/today", response_model=list[DoseOut])
async def todays_doses(tz_offset_minutes: int = Query(default=300, ge=-720, le=840),
                       user: dict = Depends(get_current_user), db=Depends(get_db)):
    now = _local_now(tz_offset_minutes)
    today = now.date()
    logs = {(l["medicine_id"], l["time"]): l async for l in
            db.medication_intake.find({"user_id": user["_id"], "day": today.isoformat()})}
    doses = []
    async for med in db.medicine_records.find({"user_id": user["_id"], "active": True}):
        if not _active_on(med, today):
            continue
        for t in med["times"]:
            log = logs.get((med["_id"], t))
            if log and log["status"] in ("taken", "skipped"):
                state = log["status"]
            else:
                due_at = datetime.combine(today, time.fromisoformat(t), tzinfo=now.tzinfo)
                minutes_late = (now - due_at).total_seconds() / 60
                state = "missed" if minutes_late > MISSED_AFTER_MINUTES else "due" if minutes_late >= -30 else "upcoming"
                if state == "missed" and not log:
                    # Record the miss once and send one notification.
                    await db.medication_intake.insert_one({"user_id": user["_id"], "medicine_id": med["_id"],
                                                           "day": today.isoformat(), "time": t, "status": "missed",
                                                           "logged_at": datetime.now(timezone.utc)})
                    await notify(db, user["_id"], "missed_dose", "Missed dose",
                                 f"You have not marked {med['name']} ({t}) as taken.", "/feature/36")
            doses.append(DoseOut(medicine_id=str(med["_id"]), name=med["name"], strength=med["strength"],
                                 time=t, status=state))
    return sorted(doses, key=lambda d: d.time)


@router.post("/{medicine_id}/intake", response_model=DoseOut)
async def log_intake(medicine_id: str, body: IntakeIn, tz_offset_minutes: int = Query(default=300, ge=-720, le=840),
                     user: dict = Depends(get_current_user), db=Depends(get_db)):
    med = await _owned(db, user, medicine_id)
    if body.time not in med["times"]:
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "invalid_time", "This medicine is not scheduled at that time.")
    day = (body.day or _local_now(tz_offset_minutes).date()).isoformat()
    await db.medication_intake.update_one(
        {"user_id": user["_id"], "medicine_id": med["_id"], "day": day, "time": body.time},
        {"$set": {"status": body.status, "logged_at": datetime.now(timezone.utc)}},
        upsert=True,
    )
    return DoseOut(medicine_id=medicine_id, name=med["name"], strength=med["strength"], time=body.time,
                   status=body.status)


@router.get("/adherence")
async def adherence(days: int = Query(default=7, ge=1, le=90), user: dict = Depends(get_current_user),
                    db=Depends(get_db)):
    """Share of logged doses that were taken (doses never opened in the app are not counted)."""
    since = (datetime.now(timezone.utc).date() - timedelta(days=days - 1)).isoformat()
    counts = {"taken": 0, "skipped": 0, "missed": 0}
    async for log in db.medication_intake.find({"user_id": user["_id"], "day": {"$gte": since}}):
        counts[log["status"]] = counts.get(log["status"], 0) + 1
    total = sum(counts.values())
    return {**counts, "days": days, "percent_taken": round(100 * counts["taken"] / total) if total else None}
