"""Help & issues: patients and doctors report a problem; the admin answers and resolves it.

Examples: payment not confirmed, doctor did not reply, wrong prescription shown, app bug, account problem.
If the issue is about a consultation, the admin sees only its status, fee and names — never the chat.
"""
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db, require_roles
from app.repositories.user_repository import to_object_id
from app.routers.notifications import notify

router = APIRouter(tags=["issues"])

Category = Literal["payment", "doctor", "consultation", "account", "app_bug", "other"]
Status = Literal["open", "in_progress", "resolved"]


class IssueIn(BaseModel):
    category: Category = "other"
    subject: str = Field(min_length=3, max_length=120)
    message: str = Field(min_length=3, max_length=2000)
    consultation_id: str | None = None


class ReplyIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


class StatusIn(BaseModel):
    status: Status


def _now() -> datetime:
    return datetime.now(timezone.utc)


async def _out(db, i: dict, admin_view: bool) -> dict:
    out = {"id": str(i["_id"]), "category": i["category"], "subject": i["subject"], "status": i["status"],
           "created_at": i["created_at"], "updated_at": i["updated_at"], "messages": i.get("messages", []),
           "user_name": i["user_name"], "user_role": i["user_role"]}
    if admin_view:
        out["user_email"] = i["user_email"]
        if i.get("consultation_id"):
            c = await db.consultations.find_one({"_id": i["consultation_id"]})
            if c:
                out["consultation"] = {"id": str(c["_id"]), "status": c["status"], "doctor_name": c["doctor_name"],
                                       "patient_name": c["patient_name"], "fee_pkr": c.get("fee_pkr"),
                                       "paid": bool(c.get("paid_at")), "created_at": c["created_at"]}
    return out


@router.post("/issues", status_code=status.HTTP_201_CREATED, dependencies=[limit_by_user("issue", 10, 3600)])
async def report_issue(body: IssueIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    cid = None
    if body.consultation_id:
        cid = to_object_id(body.consultation_id)
        c = await db.consultations.find_one({"_id": cid}) if cid else None
        doctor = await db.doctors.find_one({"_id": c["doctor_id"]}) if c else None
        if c is None or user["_id"] not in (c["user_id"], (doctor or {}).get("user_id")):
            raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Consultation not found.")
    now = _now()
    role = "admin" if "admin" in user["roles"] else "doctor" if "doctor" in user["roles"] else "patient"
    doc = {"user_id": user["_id"], "user_name": user["full_name"], "user_email": user["email"], "user_role": role,
           "category": body.category, "subject": body.subject.strip(), "status": "open", "consultation_id": cid,
           "messages": [{"from": "user", "name": user["full_name"], "text": body.message.strip(), "at": now}],
           "created_at": now, "updated_at": now}
    doc["_id"] = (await db.issues.insert_one(doc)).inserted_id
    async for admin in db.users.find({"roles": "admin"}, {"_id": 1}):
        await notify(db, admin["_id"], "issue", f"New issue: {doc['subject']}", f"{user['full_name']} ({role})",
                     link="/admin")
    return await _out(db, doc, admin_view=False)


@router.get("/issues")
async def my_issues(user: dict = Depends(get_current_user), db=Depends(get_db)):
    return [await _out(db, i, False) async for i in db.issues.find({"user_id": user["_id"]}).sort("updated_at", -1)]


async def _issue(db, issue_id: str) -> dict:
    oid = to_object_id(issue_id)
    i = await db.issues.find_one({"_id": oid}) if oid else None
    if i is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Issue not found.")
    return i


@router.post("/issues/{issue_id}/messages")
async def reply(issue_id: str, body: ReplyIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    i = await _issue(db, issue_id)
    is_admin = "admin" in user["roles"]
    if not is_admin and i["user_id"] != user["_id"]:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Issue not found.")
    msg = {"from": "admin" if is_admin else "user", "name": "Support team" if is_admin else user["full_name"],
           "text": body.text.strip(), "at": _now()}
    new_status = "in_progress" if is_admin and i["status"] == "open" else ("open" if not is_admin else i["status"])
    await db.issues.update_one({"_id": i["_id"]}, {"$push": {"messages": msg},
                                                   "$set": {"updated_at": msg["at"], "status": new_status}})
    if is_admin:
        await notify(db, i["user_id"], "issue", f"Reply to: {i['subject']}", body.text[:120], link="/issues")
    return await _out(db, await _issue(db, issue_id), admin_view=is_admin)


@router.get("/admin/issues")
async def all_issues(status_filter: Status | None = None, _: dict = Depends(require_roles("admin")),
                     db=Depends(get_db)):
    query = {"status": status_filter} if status_filter else {}
    items = [await _out(db, i, True) async for i in db.issues.find(query).sort("updated_at", -1).limit(300)]
    items.sort(key=lambda x: {"open": 0, "in_progress": 1, "resolved": 2}[x["status"]])
    return items


@router.post("/admin/issues/{issue_id}/status")
async def set_status(issue_id: str, body: StatusIn, _: dict = Depends(require_roles("admin")), db=Depends(get_db)):
    i = await _issue(db, issue_id)
    await db.issues.update_one({"_id": i["_id"]}, {"$set": {"status": body.status, "updated_at": _now()}})
    if body.status == "resolved":
        await notify(db, i["user_id"], "issue", f"Resolved: {i['subject']}",
                     "The support team marked your issue as resolved.", link="/issues")
    return await _out(db, await _issue(db, issue_id), admin_view=True)
