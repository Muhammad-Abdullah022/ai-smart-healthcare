"""All database reads/writes for users, profiles, tokens and audit events.

Keeping database code here (instead of inside the API routes) makes the
routes short and easy to read.
"""
from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId
from motor.motor_asyncio import AsyncIOMotorDatabase
from pymongo.errors import DuplicateKeyError


def _now() -> datetime:
    return datetime.now(timezone.utc)


def to_object_id(value: str) -> ObjectId | None:
    try:
        return ObjectId(value)
    except (InvalidId, TypeError):
        return None


class UserRepository:
    def __init__(self, db: AsyncIOMotorDatabase):
        self.db = db

    # ----- users -----
    async def create_user(self, email: str, password_hash: str, full_name: str) -> dict | None:
        """Create user + empty profile. Returns None if the email is already used."""
        doc = {
            "email": email.lower(),
            "password_hash": password_hash,
            "full_name": full_name,
            "roles": ["patient"],
            "email_verified": False,
            "created_at": _now(),
            "last_login": None,
        }
        try:
            result = await self.db.users.insert_one(doc)
        except DuplicateKeyError:
            return None
        doc["_id"] = result.inserted_id
        await self.db.profiles.insert_one(
            {
                "user_id": result.inserted_id,
                "blood_group": "Unknown",
                "allergies": [],
                "conditions": [],
                "emergency_contacts": [],
                "language": "en",
                "updated_at": _now(),
            }
        )
        return doc

    async def find_by_email(self, email: str) -> dict | None:
        return await self.db.users.find_one({"email": email.lower()})

    async def find_by_id(self, user_id: str) -> dict | None:
        oid = to_object_id(user_id)
        if oid is None:
            return None
        return await self.db.users.find_one({"_id": oid})

    async def mark_login(self, user_id: ObjectId) -> None:
        await self.db.users.update_one({"_id": user_id}, {"$set": {"last_login": _now()}})

    async def update_name(self, user_id: ObjectId, full_name: str) -> None:
        await self.db.users.update_one({"_id": user_id}, {"$set": {"full_name": full_name}})

    # ----- profiles -----
    async def get_profile(self, user_id: ObjectId) -> dict | None:
        return await self.db.profiles.find_one({"user_id": user_id})

    async def update_profile(self, user_id: ObjectId, changes: dict) -> None:
        changes["updated_at"] = _now()
        await self.db.profiles.update_one({"user_id": user_id}, {"$set": changes}, upsert=True)

    # ----- refresh tokens -----
    async def save_refresh_token(self, user_id: ObjectId, token_hash: str, expires_at: datetime) -> None:
        await self.db.refresh_tokens.insert_one(
            {"user_id": user_id, "token_hash": token_hash, "expires_at": expires_at,
             "revoked": False, "created_at": _now()}
        )

    async def find_active_refresh_token(self, token_hash: str) -> dict | None:
        return await self.db.refresh_tokens.find_one({"token_hash": token_hash, "revoked": False})

    async def revoke_refresh_token(self, token_hash: str) -> None:
        await self.db.refresh_tokens.update_one({"token_hash": token_hash}, {"$set": {"revoked": True}})

    # ----- audit -----
    async def audit(self, user_id: ObjectId | None, action: str, details: dict | None = None) -> None:
        """Append-only log of sensitive actions. Never store passwords or tokens here."""
        await self.db.audit_events.insert_one(
            {"user_id": user_id, "action": action, "details": details or {}, "created_at": _now()}
        )
