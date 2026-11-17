"""Admin panel (task C-11): approves doctor sign-ups, manages all accounts, handles reported issues.

Admins never see patients' health data or chats — only counts, names, emails and the issues users send.
The first admin is made on the PC with RUN\\MAKE_ADMIN.bat (scripts/make_admin.py).
"""
import re
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field, field_validator

from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.mailer import MailNotConfigured, send_mail
from app.core.security import hash_password
from app.deps import get_db, require_roles
from app.repositories.user_repository import to_object_id
from app.routers.consultations import DoctorJoin, _panel_out, save_doctor_profile
from app.routers.notifications import notify

router = APIRouter(prefix="/admin", tags=["admin"])
admin_only = require_roles("admin")


def _strong(value: str) -> str:
    if not re.search(r"[A-Za-z]", value) or not re.search(r"\d", value):
        raise ValueError("Password must contain at least one letter and one number")
    return value


class ResetPasswordIn(BaseModel):
    password: str = Field(min_length=8, max_length=128)

    _check = field_validator("password")(classmethod(lambda cls, v: _strong(v)))


class StatusIn(BaseModel):
    active: bool


async def _audit(db, admin, action: str, details: dict) -> None:
    await db.audit_events.insert_one({"user_id": admin["_id"], "action": action, "details": details,
                                      "created_at": datetime.now(timezone.utc)})


@router.get("/stats")
async def stats(_: dict = Depends(admin_only), db=Depends(get_db)):
    by_status: dict[str, int] = {}
    fees = 0.0
    async for c in db.consultations.find({}, {"status": 1, "paid_at": 1, "fee_pkr": 1}):
        by_status[c["status"]] = by_status.get(c["status"], 0) + 1
        if c.get("paid_at"):
            fees += c.get("fee_pkr") or 0
    return {
        "users": await db.users.count_documents({}),
        "patients": await db.users.count_documents({"roles": "patient"}),
        "doctors": await db.doctors.count_documents({"user_id": {"$exists": True}}),
        "pending_doctors": await db.users.count_documents({"approval": "pending"}),
        "open_issues": await db.issues.count_documents({"status": {"$ne": "resolved"}}),
        "active_doctors": await db.doctors.count_documents({"user_id": {"$exists": True}, "available": True}),
        "listed_doctors": await db.doctors.count_documents({"user_id": {"$exists": False}}),
        "consultations": sum(by_status.values()),
        "consultations_by_status": by_status,
        "fees_confirmed_pkr": fees,
        "symptom_assessments": await db.symptom_assessments.count_documents({}),
        "emergency_assessments": await db.symptom_assessments.count_documents({"emergency": True}),
        "reports": await db.medical_reports.count_documents({}),
        "prescriptions": await db.prescriptions.count_documents({}),
    }


async def _doctor_row(db, d: dict) -> dict:
    user = await db.users.find_one({"_id": d["user_id"]}) or {}
    total = await db.consultations.count_documents({"doctor_id": d["_id"]})
    active = await db.consultations.count_documents(
        {"doctor_id": d["_id"], "status": {"$nin": ["completed", "declined", "cancelled"]}})
    return {**_panel_out(d), "email": user.get("email", ""), "active": not user.get("disabled", False),
            "approval": user.get("approval", "approved"), "rejection_reason": user.get("rejection_reason", ""),
            "joined_at": d.get("joined_at"),
            "must_change_password": bool(user.get("must_change_password")),
            "last_login": user.get("last_login"), "consultations": total, "open_consultations": active}


@router.get("/doctors")
async def list_doctors(q: str | None = None, _: dict = Depends(admin_only), db=Depends(get_db)):
    query: dict = {"user_id": {"$exists": True}}
    if q:
        rx = re.compile(re.escape(q.strip()), re.IGNORECASE)
        query["$or"] = [{"name": rx}, {"specialty": rx}, {"city": rx}, {"pmdc_number": rx}]
    rows = [await _doctor_row(db, d) async for d in db.doctors.find(query).sort("joined_at", -1).limit(500)]
    order = {"pending": 0, "approved": 1, "rejected": 2}
    rows.sort(key=lambda r: order.get(r["approval"], 1))  # waiting for approval first
    return rows


class RejectIn(BaseModel):
    reason: str = Field(default="", max_length=300)


async def _tell_doctor(db, user: dict, subject: str, text: str) -> None:
    """Email the doctor (if email sending is set up) and leave an in-app notification."""
    await notify(db, user["_id"], "account", subject, text)
    try:
        await send_mail(get_settings(), user["email"], subject, text)
    except MailNotConfigured:
        pass
    except Exception as exc:  # network problem: the in-app notification is enough
        print(f"[mail] {exc}")


@router.post("/doctors/{doctor_id}/approve")
async def approve_doctor(doctor_id: str, admin: dict = Depends(admin_only), db=Depends(get_db)):
    d = await _get_doctor(db, doctor_id)
    await db.users.update_one({"_id": d["user_id"]}, {"$set": {"approval": "approved", "disabled": False},
                                                      "$unset": {"rejection_reason": ""}})
    await db.doctors.update_one({"_id": d["_id"]}, {"$set": {"approved": True, "available": True,
                                                             "approved_at": datetime.now(timezone.utc)}})
    user = await db.users.find_one({"_id": d["user_id"]})
    await _tell_doctor(db, user, "Your doctor account is approved",
                       f"Dear {d['name']},\n\nYour doctor account on AI Smart Healthcare has been approved. "
                       "You can now log in and receive online consultations.")
    await _audit(db, admin, "admin.approve_doctor", {"doctor_id": doctor_id})
    return await _doctor_row(db, await _get_doctor(db, doctor_id))


@router.post("/doctors/{doctor_id}/reject")
async def reject_doctor(doctor_id: str, body: RejectIn, admin: dict = Depends(admin_only), db=Depends(get_db)):
    d = await _get_doctor(db, doctor_id)
    await db.users.update_one({"_id": d["user_id"]}, {"$set": {"approval": "rejected",
                                                               "rejection_reason": body.reason.strip()}})
    await db.doctors.update_one({"_id": d["_id"]}, {"$set": {"approved": False, "available": False}})
    await db.refresh_tokens.update_many({"user_id": d["user_id"]}, {"$set": {"revoked": True}})
    user = await db.users.find_one({"_id": d["user_id"]})
    await _tell_doctor(db, user, "Your doctor account was not approved",
                       f"Dear {d['name']},\n\nYour doctor account was not approved. {body.reason}".strip())
    await _audit(db, admin, "admin.reject_doctor", {"doctor_id": doctor_id})
    return await _doctor_row(db, await _get_doctor(db, doctor_id))


async def _get_doctor(db, doctor_id: str) -> dict:
    oid = to_object_id(doctor_id)
    d = await db.doctors.find_one({"_id": oid, "user_id": {"$exists": True}}) if oid else None
    if d is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Doctor account not found.")
    return d


@router.put("/doctors/{doctor_id}")
async def update_doctor(doctor_id: str, body: DoctorJoin, admin: dict = Depends(admin_only), db=Depends(get_db)):
    d = await _get_doctor(db, doctor_id)
    d = await save_doctor_profile(db, d["user_id"], body)
    await db.users.update_one({"_id": d["user_id"]}, {"$set": {"full_name": d["name"]}})
    await _audit(db, admin, "admin.update_doctor", {"doctor_id": doctor_id})
    return await _doctor_row(db, d)


@router.post("/doctors/{doctor_id}/status")
async def set_doctor_status(doctor_id: str, body: StatusIn, admin: dict = Depends(admin_only), db=Depends(get_db)):
    """Disable a doctor (cannot log in, hidden from online consultations) or enable again."""
    d = await _get_doctor(db, doctor_id)
    await db.users.update_one({"_id": d["user_id"]}, {"$set": {"disabled": not body.active}})
    await db.doctors.update_one({"_id": d["_id"]}, {"$set": {"available": body.active}})
    if not body.active:
        await db.refresh_tokens.update_many({"user_id": d["user_id"]}, {"$set": {"revoked": True}})
    await _audit(db, admin, "admin.doctor_status", {"doctor_id": doctor_id, "active": body.active})
    return await _doctor_row(db, await _get_doctor(db, doctor_id))


@router.post("/doctors/{doctor_id}/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_doctor_password(doctor_id: str, body: ResetPasswordIn, admin: dict = Depends(admin_only),
                                db=Depends(get_db)):
    d = await _get_doctor(db, doctor_id)
    await db.users.update_one({"_id": d["user_id"]}, {"$set": {
        "password_hash": hash_password(body.password), "must_change_password": True}})
    await db.refresh_tokens.update_many({"user_id": d["user_id"]}, {"$set": {"revoked": True}})
    await _audit(db, admin, "admin.reset_password", {"doctor_id": doctor_id})


@router.get("/users")
async def list_users(q: str | None = None, limit: int = Query(200, ge=1, le=500),
                     _: dict = Depends(admin_only), db=Depends(get_db)):
    """Names, emails and roles only — no health data."""
    query: dict = {}
    if q:
        rx = re.compile(re.escape(q.strip()), re.IGNORECASE)
        query["$or"] = [{"full_name": rx}, {"email": rx}]
    return [{"id": str(u["_id"]), "full_name": u["full_name"], "email": u["email"], "roles": u.get("roles", []),
             "active": not u.get("disabled", False), "approval": u.get("approval", ""), "created_at": u.get("created_at"),
             "last_login": u.get("last_login")}
            async for u in db.users.find(query).sort("created_at", -1).limit(limit)]


@router.post("/users/{user_id}/status")
async def set_user_status(user_id: str, body: StatusIn, admin: dict = Depends(admin_only), db=Depends(get_db)):
    oid = to_object_id(user_id)
    user = await db.users.find_one({"_id": oid}) if oid else None
    if user is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "User not found.")
    if user["_id"] == admin["_id"]:
        raise ApiError(status.HTTP_409_CONFLICT, "self", "You cannot disable your own account.")
    await db.users.update_one({"_id": oid}, {"$set": {"disabled": not body.active}})
    if not body.active:
        await db.refresh_tokens.update_many({"user_id": oid}, {"$set": {"revoked": True}})
    await db.doctors.update_many({"user_id": oid}, {"$set": {"available": body.active}})
    await _audit(db, admin, "admin.user_status", {"user_id": user_id, "active": body.active})
    return {"id": user_id, "active": body.active}
