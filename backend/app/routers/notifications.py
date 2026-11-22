"""In-app notification center (task C-10 / B-15).

Other features call `notify(db, user_id, ...)` to add a notification.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel

from app.core.errors import ApiError
from app.deps import get_current_user, get_db
from app.repositories.user_repository import to_object_id

router = APIRouter(prefix="/notifications", tags=["notifications"])


class NotificationOut(BaseModel):
    id: str
    type: str
    title: str
    body: str
    link: str | None
    read: bool
    created_at: datetime


async def notify(db, user_id, type_: str, title: str, body: str, link: str | None = None) -> None:
    await db.notifications.insert_one({
        "user_id": user_id, "type": type_, "title": title, "body": body, "link": link,
        "read": False, "created_at": datetime.now(timezone.utc),
    })
    # Also push it live, so an open app shows a phone notification straight away.
    from app.realtime import hub  # local import: realtime is optional in some tests
    await hub.send([user_id], {"type": "notification", "kind": type_, "title": title, "body": body, "link": link})


def _out(d: dict) -> NotificationOut:
    return NotificationOut(id=str(d["_id"]), type=d["type"], title=d["title"], body=d["body"],
                           link=d.get("link"), read=d["read"], created_at=d["created_at"])


@router.get("", response_model=list[NotificationOut])
async def list_notifications(user: dict = Depends(get_current_user), db=Depends(get_db)):
    cursor = db.notifications.find({"user_id": user["_id"]}).sort("created_at", -1).limit(100)
    return [_out(d) async for d in cursor]


@router.post("/{notification_id}/read", response_model=NotificationOut)
async def mark_read(notification_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    oid = to_object_id(notification_id)
    query = {"_id": oid, "user_id": user["_id"]}
    result = await db.notifications.update_one(query, {"$set": {"read": True}}) if oid else None
    if result is None or result.matched_count == 0:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Notification not found.")
    return _out(await db.notifications.find_one(query))


@router.post("/read-all", status_code=status.HTTP_204_NO_CONTENT)
async def mark_all_read(user: dict = Depends(get_current_user), db=Depends(get_db)):
    await db.notifications.update_many({"user_id": user["_id"], "read": False}, {"$set": {"read": True}})
