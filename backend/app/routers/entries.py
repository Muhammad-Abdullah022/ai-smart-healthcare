"""Generic per-feature storage (UI-first phase).

Every feature screen can save what the user enters, so data reaches MongoDB
before each feature's dedicated logic (AI, verified data sources, etc.) is built.
Entries are private to their owner. Values are limited to simple types and sizes.
"""
import re
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Path, status
from pydantic import BaseModel, field_validator

from app.core.errors import ApiError
from app.deps import get_current_user, get_db
from app.repositories.user_repository import to_object_id

router = APIRouter(prefix="/entries", tags=["feature entries"])
_KEY = re.compile(r"^[a-z][a-z0-9_]{0,39}$")
Value = str | int | float | bool | list[str] | None


class EntryIn(BaseModel):
    data: dict[str, Value]

    @field_validator("data")
    @classmethod
    def limits(cls, data: dict) -> dict:
        if not data:
            raise ValueError("Nothing to save")
        if len(data) > 30:
            raise ValueError("Too many fields")
        for key, value in data.items():
            if not _KEY.match(key):
                raise ValueError(f"Invalid field name: {key}")
            if isinstance(value, str) and len(value) > 2000:
                raise ValueError(f"{key} is too long")
            if isinstance(value, list) and (len(value) > 50 or any(len(v) > 200 for v in value)):
                raise ValueError(f"{key} has too many or too long items")
        return data


class EntryOut(BaseModel):
    id: str
    feature: int
    data: dict
    created_at: datetime


Feature = Path(ge=1, le=50)


def _out(d: dict) -> EntryOut:
    return EntryOut(id=str(d["_id"]), feature=d["feature"], data=d["data"], created_at=d["created_at"])


@router.post("/{feature}", response_model=EntryOut, status_code=status.HTTP_201_CREATED)
async def add_entry(body: EntryIn, feature: int = Feature, user: dict = Depends(get_current_user), db=Depends(get_db)):
    doc = {"user_id": user["_id"], "feature": feature, "data": body.data, "archived": False,
           "created_at": datetime.now(timezone.utc)}
    doc["_id"] = (await db.feature_entries.insert_one(doc)).inserted_id
    return _out(doc)


@router.get("/{feature}", response_model=list[EntryOut])
async def list_entries(feature: int = Feature, user: dict = Depends(get_current_user), db=Depends(get_db)):
    cursor = db.feature_entries.find({"user_id": user["_id"], "feature": feature, "archived": False}) \
        .sort("created_at", -1).limit(100)
    return [_out(d) async for d in cursor]


@router.post("/{feature}/{entry_id}/archive", status_code=status.HTTP_204_NO_CONTENT)
async def archive_entry(entry_id: str, feature: int = Feature, user: dict = Depends(get_current_user),
                        db=Depends(get_db)):
    oid = to_object_id(entry_id)
    result = await db.feature_entries.update_one(
        {"_id": oid, "user_id": user["_id"], "feature": feature}, {"$set": {"archived": True}}) if oid else None
    if result is None or result.matched_count == 0:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Entry not found.")
