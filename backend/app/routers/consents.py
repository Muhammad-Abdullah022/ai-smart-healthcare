"""Consent records (task C-15, feature 48).

Every change is stored as a new record (never overwritten), so there is a full
history of what the user agreed to, when, and to which version of the wording.
Features check `has_consent()` before collecting optional sensitive data.
"""
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel

from app.core.errors import ApiError
from app.deps import get_current_user, get_db

router = APIRouter(prefix="/consents", tags=["consents"])

ConsentCategory = Literal[
    "ai_processing",       # sending my health text to AI providers
    "mental_health",       # storing mental health answers and mood
    "location",            # using my location (SOS, nearby services)
    "camera",              # camera features (scanning, exercise)
    "microphone",          # voice assistant
    "caregiver_sharing",   # sharing data with family/caregivers
]
CURRENT_VERSION = "2026-11-01"

DESCRIPTIONS = {
    "ai_processing": "Send the health details you type to our AI providers (Google Gemini / Groq) to get a response.",
    "mental_health": "Save your mental health questionnaire answers and daily mood privately in your account.",
    "location": "Use your location only when you press SOS or search for nearby services.",
    "camera": "Use your camera only when you scan a document or use exercise monitoring.",
    "microphone": "Use your microphone only while the voice assistant is listening.",
    "caregiver_sharing": "Let family members or caregivers you choose see parts of your health data.",
}


class ConsentChange(BaseModel):
    category: ConsentCategory
    granted: bool


class ConsentState(BaseModel):
    category: str
    description: str
    granted: bool
    version: str | None
    updated_at: datetime | None


async def has_consent(db, user_id, category: str) -> bool:
    latest = await db.consents.find_one({"user_id": user_id, "category": category}, sort=[("created_at", -1)])
    return bool(latest and latest["granted"])


async def require_consent(db, user_id, category: str) -> None:
    if not await has_consent(db, user_id, category):
        raise ApiError(status.HTTP_403_FORBIDDEN, "consent_required",
                       f"Please allow '{category.replace('_', ' ')}' in Privacy & consent first.")


@router.get("", response_model=list[ConsentState])
async def list_consents(user: dict = Depends(get_current_user), db=Depends(get_db)):
    states = []
    for category, description in DESCRIPTIONS.items():
        latest = await db.consents.find_one({"user_id": user["_id"], "category": category},
                                            sort=[("created_at", -1)])
        states.append(ConsentState(
            category=category, description=description,
            granted=bool(latest and latest["granted"]),
            version=latest["version"] if latest else None,
            updated_at=latest["created_at"] if latest else None,
        ))
    return states


@router.post("", response_model=ConsentState, status_code=status.HTTP_201_CREATED)
async def change_consent(body: ConsentChange, user: dict = Depends(get_current_user), db=Depends(get_db)):
    now = datetime.now(timezone.utc)
    await db.consents.insert_one({"user_id": user["_id"], "category": body.category, "granted": body.granted,
                                  "version": CURRENT_VERSION, "created_at": now})
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "consent.change",
                                      "details": {"category": body.category, "granted": body.granted},
                                      "created_at": now})
    return ConsentState(category=body.category, description=DESCRIPTIONS[body.category],
                        granted=body.granted, version=CURRENT_VERSION, updated_at=now)
