"""Online doctor consultations and the doctor panel.

Flow
  1. The AI chatbot recommends a specialist -> the patient picks a doctor who has joined the app
     ("Online" badge) and sends a consultation request (optionally sharing the latest symptom check).
  2. The doctor sees it live in the doctor panel and accepts (or declines).
  3. The patient pays the fee to the doctor's JazzCash / Easypaisa / bank account and uploads the
     payment screenshot. The AI reads the amount and transaction ID to help the doctor check it.
  4. The doctor confirms the payment. Only then can the doctor send a prescription (medicines); the
     patient checks it and can turn it into medicine reminders (same flow as the prescription reader).
  5. For a serious problem the doctor asks the patient to visit the clinic instead (address and timings
     are sent in the chat; for an emergency the app shows 1122).

Messages are saved in MongoDB and pushed live over the WebSocket hub (app/realtime.py).
The app never moves money: the patient pays outside the app and the doctor confirms receipt.
"""
import base64
import hashlib
import re
from datetime import date, datetime, timezone
from typing import Literal

from bson import Binary
from fastapi import APIRouter, Depends, File, Form, Request, UploadFile, status
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db
from app.doctors import normalize_specialty
from app.models.doctor import DoctorJoin  # noqa: F401  (re-exported for admin)
from app.health.record import age_of
from app.realtime import hub
from app.repositories.user_repository import to_object_id
from app.routers.assessments import get_ai_service
from app.routers.notifications import notify

router = APIRouter(tags=["consultations"])

IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_BYTES = 6 * 1024 * 1024
ACTIVE = ("requested", "awaiting_payment", "payment_submitted", "paid", "advised", "visit_clinic")
STATUS_TEXT = {
    "requested": "Waiting for the doctor to accept",
    "awaiting_payment": "Accepted — please pay the fee and upload the screenshot",
    "payment_submitted": "Payment screenshot sent — doctor is checking it",
    "paid": "Payment confirmed — the doctor will send advice",
    "advised": "Prescription sent",
    "visit_clinic": "Doctor asked you to visit the clinic",
    "declined": "Declined by the doctor",
    "cancelled": "Cancelled",
    "completed": "Completed",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _key(text: str) -> str:
    return " ".join(text.lower().split())


# ---------------------------------------------------------------- doctor panel (join / profile)

def _panel_out(d: dict) -> dict:
    return {"id": str(d["_id"]), "name": d["name"], "pmdc_number": d.get("pmdc_number", ""),
            "specialty": d["specialty"], "qualification": d["qualification"], "city": d["city"],
            "clinic": d["clinic"], "address": d["address"], "phone": d["phone"], "timings": d["timings"],
            "fee_pkr": d["fee_pkr"], "payment_method": d.get("payment_method", ""),
            "payment_title": d.get("payment_title", ""), "payment_account": d.get("payment_account", ""),
            "experience_years": d.get("experience_years"), "gender": d.get("gender", ""),
            "about": d.get("about", ""), "available": d.get("available", True)}


async def _my_doctor(db, user) -> dict:
    d = await db.doctors.find_one({"user_id": user["_id"]})
    if d is None:
        raise ApiError(status.HTTP_403_FORBIDDEN, "not_doctor",
                       "This is not a doctor account. Doctor accounts are created by the administrator.")
    return d


async def save_doctor_profile(db, user_id, body: DoctorJoin) -> dict:
    """Create or update the doctor profile linked to a login (used by the admin panel and the doctor)."""
    spec = normalize_specialty(body.specialty) or body.specialty.strip().title()
    name = body.name.strip()
    if not re.match(r"^(dr|prof)\.?\s", name, re.IGNORECASE):
        name = "Dr. " + name
    data = {**body.model_dump(), "name": name, "specialty": spec, "city": body.city.strip().title(),
            "city_key": _key(body.city), "fee_pkr": float(body.fee_pkr), "email": "", "source_url": "",
            "checked": date.today().isoformat(), "demo": False, "online": True, "user_id": user_id,
            "updated_at": _now()}
    existing = await db.doctors.find_one({"user_id": user_id})
    if existing:
        await db.doctors.update_one({"_id": existing["_id"]}, {"$set": data})
    else:
        data["joined_at"] = _now()
        await db.doctors.insert_one(data)
    return await db.doctors.find_one({"user_id": user_id})


@router.put("/doctor-panel/me")
async def update_my_profile(body: DoctorJoin, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """A doctor edits their own profile (fee, timings, payment account, available).
    Doctor accounts are created only by the administrator (admin panel)."""
    await _my_doctor(db, user)
    return _panel_out(await save_doctor_profile(db, user["_id"], body))


@router.get("/doctor-panel/me")
async def my_doctor_profile(user: dict = Depends(get_current_user), db=Depends(get_db)):
    return _panel_out(await _my_doctor(db, user))


@router.get("/doctor-panel/consultations")
async def doctor_consultations(user: dict = Depends(get_current_user), db=Depends(get_db)):
    doc = await _my_doctor(db, user)
    items = [await _summary(db, c, "doctor") async for c in
             db.consultations.find({"doctor_id": doc["_id"]}).sort("updated_at", -1).limit(200)]
    stats = {"new": sum(i["status"] == "requested" for i in items),
             "to_check": sum(i["status"] == "payment_submitted" for i in items),
             "to_advise": sum(i["status"] == "paid" for i in items),
             "earned_pkr": sum(i["fee_pkr"] or 0 for i in items if i["paid"])}
    return {"doctor": _panel_out(doc), "stats": stats, "consultations": items}


# ---------------------------------------------------------------- consultations

class ConsultRequest(BaseModel):
    doctor_id: str
    reason: str = Field(min_length=3, max_length=800)
    share_assessment: bool = Field(default=False, description="Patient agreed to share the latest symptom check")
    source: Literal["chat", "doctor_list", "record"] = "doctor_list"


class MessageIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


class DeclineIn(BaseModel):
    reason: str = Field(default="", max_length=300)


class VerifyIn(BaseModel):
    ok: bool
    note: str = Field(default="", max_length=300)


class RxLine(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    strength: str = Field(default="", max_length=40)
    form: str = Field(default="", max_length=30)
    how_to_take: str = Field(min_length=2, max_length=240, description="e.g. 1 tablet morning and night after food")
    times_per_day: int | None = Field(default=None, ge=0, le=8)
    timing: str = Field(default="", max_length=80)
    duration_days: int | None = Field(default=None, ge=0, le=365)


class PrescribeIn(BaseModel):
    diagnosis: str = Field(default="", max_length=200)
    medicines: list[RxLine] = Field(min_length=1, max_length=15)
    advice: str = Field(default="", max_length=800)
    tests: list[str] = Field(default_factory=list, max_length=8)
    follow_up: str = Field(default="", max_length=120)


class ClinicVisitIn(BaseModel):
    urgency: Literal["emergency", "today", "within_3_days", "this_week"] = "today"
    reason: str = Field(min_length=3, max_length=500)
    date: str = Field(default="", max_length=40, description="Suggested day/time, free text")


class PaymentRead(BaseModel):
    looks_like_payment: bool = False
    app: str = Field(default="", max_length=40)
    amount_pkr: float | None = None
    transaction_id: str = Field(default="", max_length=40)
    paid_to: str = Field(default="", max_length=80)
    date: str = Field(default="", max_length=40)


async def _load(db, user, cid: str) -> tuple[dict, str, dict]:
    """Return (consultation, role, doctor). Only the patient and the doctor may open it."""
    oid = to_object_id(cid)
    c = await db.consultations.find_one({"_id": oid}) if oid else None
    if c is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Consultation not found.")
    doctor = await db.doctors.find_one({"_id": c["doctor_id"]}) or {}
    if c["user_id"] == user["_id"]:
        return c, "patient", doctor
    if doctor.get("user_id") == user["_id"]:
        return c, "doctor", doctor
    raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Consultation not found.")


def _need(role: str, wanted: str):
    if role != wanted:
        raise ApiError(status.HTTP_403_FORBIDDEN, "forbidden", f"Only the {wanted} can do this.")


def _need_status(c: dict, *allowed: str, message: str):
    if c["status"] not in allowed:
        raise ApiError(status.HTTP_409_CONFLICT, "wrong_status", message)


def _msg_out(m: dict) -> dict:
    return {"id": str(m["_id"]), "sender": m["sender"], "kind": m["kind"], "text": m.get("text", ""),
            "meta": m.get("meta", {}), "created_at": m["created_at"]}


async def _summary(db, c: dict, role: str) -> dict:
    last = await db.consult_messages.find_one({"consultation_id": c["_id"]}, sort=[("created_at", -1)])
    return {"id": str(c["_id"]), "status": c["status"], "status_text": STATUS_TEXT.get(c["status"], ""),
            "doctor_name": c["doctor_name"], "specialty": c["specialty"], "patient_name": c["patient_name"],
            "reason": c["reason"], "fee_pkr": c.get("fee_pkr"), "paid": bool(c.get("paid_at")),
            "created_at": c["created_at"], "updated_at": c["updated_at"],
            "unread": c.get(f"unread_{role}", 0),
            "last_message": (last or {}).get("text", "")[:120]}


async def _post(db, c: dict, sender: str, kind: str, text: str, meta: dict | None = None,
                new_status: str | None = None) -> dict:
    """Save a message, bump the other side's unread count, push it live to both sides."""
    now = _now()
    m = {"consultation_id": c["_id"], "sender": sender, "kind": kind, "text": text, "meta": meta or {},
         "created_at": now}
    m["_id"] = (await db.consult_messages.insert_one(m)).inserted_id
    update: dict = {"$set": {"updated_at": now}}
    if new_status:
        update["$set"]["status"] = new_status
        c["status"] = new_status
    if sender in ("patient", "system"):
        update.setdefault("$inc", {})["unread_doctor"] = 1
    if sender in ("doctor", "system"):
        update.setdefault("$inc", {})["unread_patient"] = 1
    await db.consultations.update_one({"_id": c["_id"]}, update)
    doctor = await db.doctors.find_one({"_id": c["doctor_id"]}, {"user_id": 1}) or {}
    await hub.send([c["user_id"], doctor.get("user_id")],
                   {"type": "message", "consultation_id": str(c["_id"]), "status": c["status"],
                    "status_text": STATUS_TEXT.get(c["status"], ""), "message": _msg_out(m)})
    return m


async def _ping(db, user_id, title: str, body: str, cid) -> None:
    await notify(db, user_id, "consultation", title, body, link=f"/consultation/{cid}")


@router.post("/consultations", status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_user("consult_request", 10, 3600)])
async def request_consultation(body: ConsultRequest, user: dict = Depends(get_current_user), db=Depends(get_db)):
    oid = to_object_id(body.doctor_id)
    doctor = await db.doctors.find_one({"_id": oid}) if oid else None
    if doctor is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Doctor not found.")
    if not doctor.get("user_id") or doctor.get("approved") is False:
        raise ApiError(status.HTTP_409_CONFLICT, "not_online",
                       "This doctor is not on the app yet. Please call the clinic or send an appointment request.")
    if doctor["user_id"] == user["_id"]:
        raise ApiError(status.HTTP_409_CONFLICT, "own_profile", "You cannot consult yourself.")
    # A doctor who is "Away" still receives the request in the doctor panel and answers later.
    open_one = await db.consultations.find_one({"user_id": user["_id"], "doctor_id": doctor["_id"],
                                                "status": {"$in": list(ACTIVE)}})
    if open_one:
        return {**await _summary(db, open_one, "patient"), "existing": True}

    profile = await db.profiles.find_one({"user_id": user["_id"]}) or {}
    now = _now()
    c = {"user_id": user["_id"], "doctor_id": doctor["_id"], "doctor_name": doctor["name"],
         "specialty": doctor["specialty"], "fee_pkr": doctor.get("fee_pkr"),
         "patient_name": profile.get("full_name") or user["full_name"], "reason": body.reason.strip(),
         "source": body.source, "status": "requested", "created_at": now, "updated_at": now,
         "unread_doctor": 0, "unread_patient": 0}
    c["_id"] = (await db.consultations.insert_one(c)).inserted_id

    await _post(db, c, "patient", "text", body.reason.strip())
    if body.share_assessment:
        a = await db.symptom_assessments.find_one({"user_id": user["_id"]}, sort=[("created_at", -1)])
        if a:
            await _post(db, c, "patient", "summary", "Shared my latest AI symptom check", meta={
                "date": a["created_at"], "symptoms": a.get("symptoms", ""), "urgency": a.get("triage_level", ""),
                "possible_causes": [x.get("name", "") for x in (a.get("possible_causes") or [])][:4],
                "specialist": a.get("specialist_type", ""),
                "otc_options": [o.get("name", "") for o in (a.get("otc_options") or [])][:5]})
    await _ping(db, doctor["user_id"], "New consultation request",
                f"{c['patient_name']}: {body.reason[:80]}", c["_id"])
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "consultation.request",
                                      "details": {"shared_assessment": body.share_assessment}, "created_at": now})
    return {**await _summary(db, c, "patient"), "existing": False}


@router.get("/consultations")
async def my_consultations(user: dict = Depends(get_current_user), db=Depends(get_db)):
    return [await _summary(db, c, "patient") async for c in
            db.consultations.find({"user_id": user["_id"]}).sort("updated_at", -1).limit(100)]


@router.get("/consultations/{cid}")
async def consultation_detail(cid: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, doctor = await _load(db, user, cid)
    await db.consultations.update_one({"_id": c["_id"]}, {"$set": {f"unread_{role}": 0}})
    msgs = [_msg_out(m) async for m in db.consult_messages.find({"consultation_id": c["_id"]}).sort("created_at", 1)]
    out = await _summary(db, c, role)
    out.update(role=role, messages=msgs, unread=0,
               doctor={"id": str(doctor.get("_id", "")), "name": doctor.get("name", c["doctor_name"]),
                       "specialty": doctor.get("specialty", ""), "qualification": doctor.get("qualification", ""),
                       "clinic": doctor.get("clinic", ""), "address": doctor.get("address", ""),
                       "city": doctor.get("city", ""), "phone": doctor.get("phone", ""),
                       "timings": doctor.get("timings", ""), "online_now": hub.online(doctor.get("user_id"))})
    # Payment details only once the doctor has accepted.
    if c["status"] not in ("requested", "declined", "cancelled"):
        out["payment"] = {"method": doctor.get("payment_method", ""), "title": doctor.get("payment_title", ""),
                          "account": doctor.get("payment_account", ""), "amount_pkr": c.get("fee_pkr")}
    if role == "doctor":
        profile = await db.profiles.find_one({"user_id": c["user_id"]}) or {}
        out["patient"] = {"name": c["patient_name"], "age": age_of(profile.get("date_of_birth")),
                          "gender": profile.get("gender"), "city": profile.get("city"),
                          "blood_group": profile.get("blood_group"), "allergies": profile.get("allergies", []),
                          "conditions": profile.get("conditions", []), "online_now": hub.online(c["user_id"])}
    return out


@router.post("/consultations/{cid}/messages", status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_user("consult_message", 120, 3600)])
async def send_message(cid: str, body: MessageIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, doctor = await _load(db, user, cid)
    _need_status(c, *ACTIVE, message="This consultation is closed.")
    m = await _post(db, c, role, "text", body.text.strip())
    other = c["user_id"] if role == "doctor" else doctor.get("user_id")
    if not hub.online(other):  # not in the app right now: leave a notification too
        await _ping(db, other, f"New message from {c['doctor_name'] if role == 'doctor' else c['patient_name']}",
                    body.text[:100], c["_id"])
    return _msg_out(m)


@router.post("/consultations/{cid}/accept")
async def accept(cid: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, doctor = await _load(db, user, cid)
    _need(role, "doctor")
    _need_status(c, "requested", message="Already answered.")
    fee = doctor.get("fee_pkr") or c.get("fee_pkr")
    if fee and not doctor.get("payment_account"):
        raise ApiError(status.HTTP_409_CONFLICT, "no_payment_account",
                       "Add your JazzCash / Easypaisa / bank account in Edit profile first, so the patient can pay.")
    if fee != c.get("fee_pkr"):
        await db.consultations.update_one({"_id": c["_id"]}, {"$set": {"fee_pkr": fee}})
        c["fee_pkr"] = fee
    if fee:
        text = (f"{doctor['name']} accepted your request. Please pay Rs {fee:,.0f} by {doctor.get('payment_method')} "
                f"to {doctor.get('payment_title')} ({doctor.get('payment_account')}) and upload the payment screenshot.")
        new_status = "awaiting_payment"
    else:
        text, new_status = f"{doctor['name']} accepted your request (no fee).", "paid"
    await _post(db, c, "system", "status", text, new_status=new_status,
                meta={"payment": {"method": doctor.get("payment_method"), "title": doctor.get("payment_title"),
                                  "account": doctor.get("payment_account"), "amount_pkr": fee}})
    if new_status == "paid":
        await db.consultations.update_one({"_id": c["_id"]}, {"$set": {"paid_at": _now()}})
    await _ping(db, c["user_id"], "Doctor accepted", text[:140], c["_id"])
    return {"status": c["status"]}


@router.post("/consultations/{cid}/decline")
async def decline(cid: str, body: DeclineIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, doctor = await _load(db, user, cid)
    _need(role, "doctor")
    _need_status(c, "requested", "awaiting_payment", message="Can only decline before payment.")
    text = f"{doctor['name']} cannot take this consultation." + (f" Reason: {body.reason}" if body.reason else "")
    await _post(db, c, "system", "status", text, new_status="declined")
    await _ping(db, c["user_id"], "Consultation declined", text[:140], c["_id"])
    return {"status": c["status"]}


@router.post("/consultations/{cid}/cancel")
async def cancel(cid: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, _ = await _load(db, user, cid)
    _need(role, "patient")
    _need_status(c, "requested", "awaiting_payment", message="It can only be cancelled before payment.")
    await _post(db, c, "system", "status", f"{c['patient_name']} cancelled the request.", new_status="cancelled")
    return {"status": c["status"]}


PAYMENT_SYSTEM = """You read a screenshot of a mobile payment (JazzCash, Easypaisa, bank app) for a doctor
who must confirm a consultation fee. Only report what is visibly written. Do not guess numbers.
looks_like_payment=false if the image is not a payment receipt. amount_pkr is the sent amount in rupees.
transaction_id is the TID / reference / transaction number. paid_to is the receiver name or number."""


@router.post("/consultations/{cid}/payment", dependencies=[limit_by_user("consult_payment", 10, 3600)])
async def upload_payment(cid: str, request: Request, file: UploadFile = File(...),
                         transaction_id: str = Form(""), user: dict = Depends(get_current_user),
                         db=Depends(get_db)):
    c, role, doctor = await _load(db, user, cid)
    _need(role, "patient")
    _need_status(c, "awaiting_payment", message="The doctor has not asked for payment, or it is already sent.")
    mime = (file.content_type or "").lower()
    if mime not in IMAGE_TYPES:
        raise ApiError(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "bad_type", "Please upload a JPG or PNG screenshot.")
    data = await file.read(MAX_BYTES + 1)
    if not data or len(data) > MAX_BYTES:
        raise ApiError(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "too_large", "The screenshot must be under 6 MB.")
    file_id = (await db.consult_files.insert_one({
        "consultation_id": c["_id"], "user_id": user["_id"], "data": Binary(data), "mime_type": mime,
        "sha256": hashlib.sha256(data).hexdigest(), "created_at": _now()})).inserted_id

    # Help the doctor: read amount / transaction ID from the screenshot (best effort, never decides).
    read: dict = {}
    try:
        result = await get_ai_service(request).generate(
            PaymentRead, PAYMENT_SYSTEM, f"Expected amount: Rs {c.get('fee_pkr') or 0:g}. "
            f"Expected receiver: {doctor.get('payment_title', '')} {doctor.get('payment_account', '')}.",
            images=[(mime, base64.b64encode(data).decode())])
        read = result.data.model_dump()
    except Exception as exc:  # AI not configured / quota / unreadable — the doctor checks the image anyway
        print(f"[consult] payment read skipped: {exc}")
    tid = transaction_id.strip()[:40] or read.get("transaction_id", "")
    amount_ok = read.get("amount_pkr") is not None and c.get("fee_pkr") is not None and \
        abs(float(read["amount_pkr"]) - float(c["fee_pkr"])) < 1
    meta = {"file_id": str(file_id), "transaction_id": tid, "ai": read, "amount_matches": amount_ok}
    await _post(db, c, "patient", "payment", "Payment screenshot uploaded" + (f" (TID {tid})" if tid else ""),
                meta=meta, new_status="payment_submitted")
    await _ping(db, doctor["user_id"], "Payment screenshot received", f"{c['patient_name']} sent the fee screenshot.",
                c["_id"])
    return {"status": c["status"], "meta": meta}


ATTACHMENT_TYPES = {
    "image/jpeg": "image", "image/png": "image", "image/webp": "image", "application/pdf": "pdf",
    "application/msword": "document",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "document",
    "text/plain": "document",
}
MAX_ATTACHMENT = 10 * 1024 * 1024


@router.post("/consultations/{cid}/attachments", status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_user("consult_attachment", 40, 3600)])
async def send_attachment(cid: str, file: UploadFile = File(...), caption: str = Form(""),
                          user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Patient or doctor sends a photo, PDF or document in the chat (e.g. old reports, X-ray, rash photo)."""
    c, role, doctor = await _load(db, user, cid)
    _need_status(c, *ACTIVE, message="This consultation is closed.")
    mime = (file.content_type or "").lower()
    # Safe file name (also used in the download header).
    name = re.sub(r"[^A-Za-z0-9 ._()-]", "_", file.filename or "file")[:120] or "file"
    if mime not in ATTACHMENT_TYPES:
        # Some phones send "application/octet-stream": decide by the file name.
        ext = name.lower().rsplit(".", 1)[-1] if "." in name else ""
        mime = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp",
                "pdf": "application/pdf", "doc": "application/msword", "txt": "text/plain",
                "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"}.get(ext, mime)
    if mime not in ATTACHMENT_TYPES:
        raise ApiError(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "bad_type",
                       "You can send photos (JPG, PNG), PDF, Word or text files.")
    data = await file.read(MAX_ATTACHMENT + 1)
    if not data:
        raise ApiError(status.HTTP_400_BAD_REQUEST, "empty", "The file is empty.")
    if len(data) > MAX_ATTACHMENT:
        raise ApiError(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "too_large", "Files must be under 10 MB.")
    file_id = (await db.consult_files.insert_one({
        "consultation_id": c["_id"], "user_id": user["_id"], "data": Binary(data), "mime_type": mime,
        "file_name": name, "sha256": hashlib.sha256(data).hexdigest(), "created_at": _now()})).inserted_id
    kind = ATTACHMENT_TYPES[mime]
    text = caption.strip()[:500] or {"image": "Photo", "pdf": f"PDF: {name}"}.get(kind, f"File: {name}")
    m = await _post(db, c, role, "file", text, meta={"file_id": str(file_id), "file_name": name, "mime_type": mime,
                                                    "file_kind": kind, "size": len(data)})
    other = c["user_id"] if role == "doctor" else doctor.get("user_id")
    if not hub.online(other):
        await _ping(db, other, f"New file from {c['doctor_name'] if role == 'doctor' else c['patient_name']}",
                    text[:100], c["_id"])
    return _msg_out(m)


@router.get("/consultations/{cid}/files/{file_id}")
async def consult_file(cid: str, file_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, _, _ = await _load(db, user, cid)
    oid = to_object_id(file_id)
    f = await db.consult_files.find_one({"_id": oid, "consultation_id": c["_id"]}) if oid else None
    if f is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "File not found.")
    name = f.get("file_name") or ("payment.jpg" if f["mime_type"].startswith("image/") else "file")
    return Response(content=bytes(f["data"]), media_type=f["mime_type"],
                    headers={"Cache-Control": "private, no-store",
                             "Content-Disposition": f'inline; filename="{name}"'})


@router.post("/consultations/{cid}/payment/verify")
async def verify_payment(cid: str, body: VerifyIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, _ = await _load(db, user, cid)
    _need(role, "doctor")
    _need_status(c, "payment_submitted", message="No payment screenshot to check.")
    if body.ok:
        await db.consultations.update_one({"_id": c["_id"]}, {"$set": {"paid_at": _now()}})
        await _post(db, c, "doctor", "payment_ok", "Payment received. Thank you!" + (f" {body.note}" if body.note else ""),
                    new_status="paid")
        await _ping(db, c["user_id"], "Payment confirmed", "The doctor confirmed your payment.", c["_id"])
    else:
        await _post(db, c, "doctor", "payment_rejected",
                    "I could not find this payment. " + (body.note or "Please check and upload the correct screenshot."),
                    new_status="awaiting_payment")
        await _ping(db, c["user_id"], "Payment not confirmed", body.note or "Please upload the correct screenshot.", c["_id"])
    return {"status": c["status"]}


@router.post("/consultations/{cid}/prescribe")
async def prescribe(cid: str, body: PrescribeIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, doctor = await _load(db, user, cid)
    _need(role, "doctor")
    _need_status(c, "paid", "advised", message="The prescription can be sent after the payment is confirmed.")
    now = _now()
    meds = [{"name": m.name, "generic_name": "", "strength": m.strength, "form": m.form,
             "dose_as_written": "", "how_to_take": m.how_to_take, "times_per_day": m.times_per_day,
             "timing": m.timing, "duration": f"{m.duration_days} days" if m.duration_days else "",
             "duration_days": m.duration_days, "purpose": "", "confidence": "high", "unclear_parts": ""}
            for m in body.medicines]
    notes = [x for x in ([f"Diagnosis: {body.diagnosis}"] if body.diagnosis else []) +
             ([f"Tests: {', '.join(body.tests)}"] if body.tests else []) +
             ([f"Follow-up: {body.follow_up}"] if body.follow_up else []) + ([body.advice] if body.advice else [])]
    # Saved as a prescription for the patient: they check it once, then it can become medicine reminders
    # and it appears in the health record (same flow as a scanned prescription).
    rx = {"user_id": c["user_id"], "file_id": None, "file_name": f"Online consultation — {doctor['name']}",
          "mime_type": "text/plain", "language": "en", "status": "needs_review", "source": "consultation",
          "consultation_id": c["_id"], "created_at": now, "prompt_version": "doctor",
          "reading": {"readable": True, "doctor_name": doctor["name"], "clinic": doctor.get("clinic", ""),
                      "date": now.date().isoformat(),
                      "summary": f"Prescription from {doctor['name']} ({doctor['specialty']}) after an online consultation."
                                 + (f" Diagnosis: {body.diagnosis}." if body.diagnosis else ""),
                      "medicines": meds, "notes": notes[:8],
                      "warnings": ["Take medicines exactly as the doctor wrote. Ask the doctor in this chat if anything is unclear."]}}
    rx_id = (await db.prescriptions.insert_one(rx)).inserted_id
    lines = [f"{m.name} {m.strength}".strip() + f" — {m.how_to_take}" +
             (f" for {m.duration_days} days" if m.duration_days else "") for m in body.medicines]
    await _post(db, c, "doctor", "prescription", "Prescription:\n" + "\n".join(lines),
                meta={"prescription_id": str(rx_id), "diagnosis": body.diagnosis, "medicines": [m.model_dump() for m in body.medicines],
                      "advice": body.advice, "tests": body.tests, "follow_up": body.follow_up},
                new_status="advised")
    await _ping(db, c["user_id"], "Prescription received", f"{doctor['name']} sent your medicines.", c["_id"])
    return {"status": c["status"], "prescription_id": str(rx_id)}


URGENCY_TEXT = {"emergency": "This may be an emergency. Go to the nearest emergency department now or call 1122.",
                "today": "Please visit the clinic today.", "within_3_days": "Please visit the clinic within 3 days.",
                "this_week": "Please visit the clinic this week."}


@router.post("/consultations/{cid}/visit-clinic")
async def visit_clinic(cid: str, body: ClinicVisitIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, doctor = await _load(db, user, cid)
    _need(role, "doctor")
    _need_status(c, "awaiting_payment", "payment_submitted", "paid", "advised", "requested",
                 message="This consultation is closed.")
    text = f"{URGENCY_TEXT[body.urgency]} Reason: {body.reason}"
    await _post(db, c, "doctor", "clinic_visit", text, new_status="visit_clinic", meta={
        "urgency": body.urgency, "reason": body.reason, "date": body.date, "clinic": doctor.get("clinic", ""),
        "address": doctor.get("address", ""), "city": doctor.get("city", ""), "phone": doctor.get("phone", ""),
        "timings": doctor.get("timings", "")})
    await db.appointments.insert_one({
        "user_id": c["user_id"], "doctor_id": doctor["_id"], "doctor_name": doctor["name"],
        "specialty": doctor["specialty"], "city": doctor.get("city", ""), "clinic": doctor.get("clinic", ""),
        "preferred_date": body.date or date.today().isoformat(), "time_of_day": "any", "reason": body.reason,
        "source": "consultation", "status": "doctor_asked_visit", "created_at": _now()})
    await _ping(db, c["user_id"], "Please visit the clinic" if body.urgency != "emergency" else "Urgent: go to hospital",
                text[:140], c["_id"])
    return {"status": c["status"]}


@router.post("/consultations/{cid}/complete")
async def complete(cid: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    c, role, _ = await _load(db, user, cid)
    _need_status(c, "paid", "advised", "visit_clinic", message="Nothing to complete yet.")
    who = c["doctor_name"] if role == "doctor" else c["patient_name"]
    await _post(db, c, "system", "status", f"{who} closed the consultation.", new_status="completed")
    return {"status": c["status"]}
