"""SOS (feature 12).

Pressing SOS records an emergency event and returns everything the app needs to
get help fast: emergency numbers, the user's emergency contacts, and a ready-made
message (with a map link if the user shared their location and allowed it).

LIMITATION: the backend does not send SMS itself yet (needs an SMS provider such
as Twilio, which costs money and needs approval). The app lets the user copy the
message and call contacts directly. This must work even if AI services are down.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from app.ai.safety import EMERGENCY_NUMBERS
from app.deps import get_current_user, get_db
from app.routers.consents import has_consent

router = APIRouter(prefix="/sos", tags=["sos"])


class SosRequest(BaseModel):
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    note: str = Field(default="", max_length=200)


class SosOut(BaseModel):
    id: str
    created_at: datetime
    emergency_numbers: list[dict]
    contacts: list[dict]
    message: str
    location_included: bool
    sms_sent: bool = False
    limitation: str


@router.post("", response_model=SosOut, status_code=status.HTTP_201_CREATED)
async def trigger_sos(body: SosRequest, user: dict = Depends(get_current_user), db=Depends(get_db)):
    profile = await db.profiles.find_one({"user_id": user["_id"]}) or {}
    has_location = body.latitude is not None and body.longitude is not None
    use_location = has_location and await has_consent(db, user["_id"], "location")

    parts = [f"EMERGENCY: {user['full_name']} needs help now."]
    if body.note:
        parts.append(body.note)
    if profile.get("blood_group") and profile["blood_group"] != "Unknown":
        parts.append(f"Blood group: {profile['blood_group']}.")
    if profile.get("allergies"):
        parts.append(f"Allergies: {', '.join(profile['allergies'])}.")
    if use_location:
        parts.append(f"Location: https://maps.google.com/?q={body.latitude:.5f},{body.longitude:.5f}")
    parts.append("Please call them or 1122.")
    message = " ".join(parts)

    now = datetime.now(timezone.utc)
    doc = {"user_id": user["_id"], "created_at": now, "note": body.note,
           "location": {"lat": body.latitude, "lng": body.longitude} if use_location else None}
    doc["_id"] = (await db.sos_events.insert_one(doc)).inserted_id
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "sos.trigger",
                                      "details": {"location": use_location}, "created_at": now})
    return SosOut(
        id=str(doc["_id"]), created_at=now, emergency_numbers=EMERGENCY_NUMBERS,
        contacts=profile.get("emergency_contacts", []), message=message, location_included=use_location,
        limitation="Messages are not sent automatically yet. Call or send the message to your contacts yourself.",
    )


@router.get("")
async def sos_history(user: dict = Depends(get_current_user), db=Depends(get_db)):
    cursor = db.sos_events.find({"user_id": user["_id"]}).sort("created_at", -1).limit(20)
    return [{"id": str(d["_id"]), "created_at": d["created_at"], "location_included": d["location"] is not None}
            async for d in cursor]
