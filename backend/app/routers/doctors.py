"""Features 10 and 11: doctor directory (Punjab) and appointment requests sent to the doctor by email.

Doctors come from the data files (backend/data/doctors): the official Punjab government list, plus
made-up demo profiles (demo_doctors.csv) that the app always labels "Demo profile".
Booking needs the user's confirmation; the request email includes only what the user agreed to send.
"""
import re
from datetime import date, datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.mailer import MailNotConfigured, send_mail
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db
from app.doctors import SPECIALTIES, normalize_specialty, specialties_for
from app.repositories.user_repository import to_object_id

router = APIRouter(tags=["doctors"])


def _key(text: str) -> str:
    return " ".join(text.lower().split())


def _doctor_out(d: dict) -> dict:
    return {"id": str(d["_id"]), "name": d["name"], "specialty": d["specialty"], "qualification": d["qualification"],
            "city": d["city"], "clinic": d["clinic"], "address": d["address"], "fee_pkr": d["fee_pkr"],
            "phone": d["phone"], "timings": d["timings"], "can_email": bool(d.get("email")),
            "source_url": d["source_url"], "checked": d["checked"],
            "experience_years": d.get("experience_years"), "gender": d.get("gender", ""),
            "about": d.get("about", ""), "demo": bool(d.get("demo")),
            "government": "govt" in d.get("qualification", "").lower(),
            # Joined the app's doctor panel: can chat, take the fee and prescribe online.
            "online": bool(d.get("user_id")) and d.get("available", True) and d.get("approved", True),
            # Has a doctor-panel login: booking goes to the doctor's panel (even while "Away").
            "has_account": bool(d.get("user_id")) and d.get("approved", True) is not False}


@router.get("/doctors/specialties")
async def specialties(city: str | None = None, db=Depends(get_db)):
    """All specialties, with how many doctors each has (in the city if given).
    Public: the doctor sign-up form uses it before login."""
    query = {"city_key": _key(city)} if city else {}
    counts: dict[str, int] = {}
    async for d in db.doctors.find(query, {"specialty": 1}):
        counts[d["specialty"]] = counts.get(d["specialty"], 0) + 1
    names = sorted(set(SPECIALTIES) | set(counts), key=lambda n: (-counts.get(n, 0), n))
    return [{"name": n, "doctors": counts.get(n, 0)} for n in names]


@router.get("/doctors/cities")
async def doctor_cities(user: dict = Depends(get_current_user), db=Depends(get_db)):
    counts: dict[str, int] = {}
    async for d in db.doctors.find({}, {"city": 1}):
        counts[d["city"]] = counts.get(d["city"], 0) + 1
    return sorted(({"city": c, "doctors": n} for c, n in counts.items()), key=lambda x: (-x["doctors"], x["city"]))


@router.get("/doctors")
async def list_doctors(city: str | None = None, specialty: str | None = None, q: str | None = None,
                       limit: int = Query(100, ge=1, le=500), user: dict = Depends(get_current_user),
                       db=Depends(get_db)):
    query: dict = {}
    if city:
        query["city_key"] = _key(city)
    spec = normalize_specialty(specialty)
    if spec:
        query["specialty"] = spec
    if q:
        rx = re.compile(re.escape(q.strip()), re.IGNORECASE)
        query["$or"] = [{"name": rx}, {"clinic": rx}, {"address": rx}]
    # Sort first, then cut: otherwise an online doctor could fall outside the first `limit` rows.
    docs = [d async for d in db.doctors.find(query)]
    # Real (government list) doctors first, then demo profiles; within each, lower fee first.
    # Doctors on the app (online consultation) first, then real (government list), then demo profiles.
    docs.sort(key=_rank)
    return {"specialty": spec, "doctors": [_doctor_out(d) for d in docs[:limit]]}


def _rank(d: dict) -> tuple:
    # Doctors on the app (online consultation, instant booking) first, then the real government list,
    # then demo profiles; lower fee first.
    return (not (d.get("user_id") and d.get("available", True) and d.get("approved", True)),
            bool(d.get("demo")), d["fee_pkr"] is None, d["fee_pkr"] or 0, d["name"])


@router.get("/doctors/recommended")
async def recommended_doctors(specialty: str, city: str | None = None, limit: int = Query(3, ge=1, le=10),
                              user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Only doctors of the specialty the AI recommended for this problem, ready to book.

    Order: the user's city, then other cities (marked). If no doctor of the main specialty exists at all,
    the backup specialty named by the AI (e.g. "/ General physician") is used and that is said clearly.
    """
    if not city:
        profile = await db.profiles.find_one({"user_id": user["_id"]}) or {}
        city = profile.get("city") or None
    wanted = specialties_for(specialty) or [normalize_specialty(specialty) or "General Physician"]
    for spec in wanted:
        local = [d async for d in db.doctors.find({"specialty": spec, **({"city_key": _key(city)} if city else {})})]
        local.sort(key=_rank)
        picked = local[:limit]
        if len(picked) < limit:
            others = [d async for d in db.doctors.find(
                {"specialty": spec, **({"city_key": {"$ne": _key(city)}} if city else {})}).limit(300)]
            others.sort(key=_rank)
            picked += others[:limit - len(picked)]
        if picked:
            return {"specialty": spec, "asked": specialty, "city": city, "backup": spec != wanted[0],
                    "total_in_city": len(local),
                    "doctors": [{**_doctor_out(d), "other_city": bool(city) and _key(d["city"]) != _key(city)}
                                for d in picked]}
    return {"specialty": wanted[0], "asked": specialty, "city": city, "backup": False, "total_in_city": 0,
            "doctors": []}


class AppointmentRequest(BaseModel):
    doctor_id: str
    preferred_date: date
    time_of_day: Literal["morning", "afternoon", "evening", "any"] = "any"
    reason: str = Field(min_length=3, max_length=600)
    phone: str | None = Field(default=None, max_length=20)
    source: Literal["chat", "doctor_list"] = "doctor_list"


@router.post("/appointments/request", status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_user("appointment_request", 10, 3600)])
async def request_appointment(body: AppointmentRequest, user: dict = Depends(get_current_user), db=Depends(get_db)):
    oid = to_object_id(body.doctor_id)
    doctor = await db.doctors.find_one({"_id": oid}) if oid else None
    if doctor is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Doctor not found.")
    if body.preferred_date < date.today():
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "past_date", "Please choose today or a later date.")
    now = datetime.now(timezone.utc)
    profile = await db.profiles.find_one({"user_id": user["_id"]}) or {}
    phone = body.phone or profile.get("phone") or ""
    doc = {"user_id": user["_id"], "doctor_id": doctor["_id"], "doctor_name": doctor["name"],
           "specialty": doctor["specialty"], "city": doctor["city"], "clinic": doctor["clinic"],
           "preferred_date": body.preferred_date.isoformat(), "time_of_day": body.time_of_day,
           "reason": body.reason, "source": body.source, "status": "saved", "created_at": now}
    doc["_id"] = (await db.appointments.insert_one(doc)).inserted_id

    message = "Request saved. The clinic was not emailed (no email on file) — please call to confirm."
    if doctor.get("email"):
        body_text = (
            f"Dear {doctor['name']},\n\n"
            f"A patient would like to book an appointment at {doctor['clinic'] or 'your clinic'}.\n\n"
            f"Patient: {user['full_name']}\n"
            f"Contact: {user['email']}" + (f", {phone}" if phone else "") + "\n"
            f"Preferred date: {body.preferred_date.strftime('%A, %d %B %Y')} ({body.time_of_day})\n"
            f"Reason: {body.reason}\n\n"
            "Please reply to this email to confirm a time.\n\n"
            "Sent through the AI Smart Healthcare app at the patient's request. "
            "This is an appointment request, not a medical report."
        )
        try:
            await send_mail(get_settings(), doctor["email"],
                            f"Appointment request: {user['full_name']} — {body.preferred_date.isoformat()}",
                            body_text, reply_to=user["email"])
            doc["status"], message = "emailed", f"Request emailed to {doctor['name']}. The clinic will reply to your email."
        except MailNotConfigured:
            doc["status"] = "email_not_configured"
            message = "Request saved. Email sending is not set up yet — please call the clinic to confirm."
        except Exception as exc:  # network or login problem: keep the request, tell the user
            print(f"[mail] {exc}")
            doc["status"] = "email_failed"
            message = "Request saved, but the email could not be sent. Please call the clinic to confirm."
        await db.appointments.update_one({"_id": doc["_id"]}, {"$set": {"status": doc["status"]}})
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "appointment.request",
                                      "details": {"status": doc["status"]}, "created_at": now})
    return {"id": str(doc["_id"]), "status": doc["status"], "message": message,
            "doctor": _doctor_out(doctor), "preferred_date": doc["preferred_date"]}


@router.get("/appointments")
async def my_appointments(user: dict = Depends(get_current_user), db=Depends(get_db)):
    cursor = db.appointments.find({"user_id": user["_id"]}).sort("created_at", -1).limit(50)
    return [{"id": str(a["_id"]), "doctor_name": a["doctor_name"], "specialty": a["specialty"], "city": a["city"],
             "clinic": a["clinic"], "preferred_date": a["preferred_date"], "time_of_day": a["time_of_day"],
             "status": a["status"], "created_at": a["created_at"]} async for a in cursor]
