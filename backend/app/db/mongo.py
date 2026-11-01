"""MongoDB connection and index setup."""
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pymongo import ASCENDING, DESCENDING


def create_client(uri: str) -> AsyncIOMotorClient:
    # tz_aware=True keeps all dates in UTC with timezone info.
    return AsyncIOMotorClient(uri, tz_aware=True, serverSelectionTimeoutMS=10000)


async def ensure_indexes(db: AsyncIOMotorDatabase) -> None:
    """Create indexes. Safe to run every time the server starts."""
    await db.users.create_index([("email", ASCENDING)], unique=True)
    await db.profiles.create_index([("user_id", ASCENDING)], unique=True)
    await db.refresh_tokens.create_index([("token_hash", ASCENDING)], unique=True)
    await db.refresh_tokens.create_index([("user_id", ASCENDING)])
    # MongoDB deletes expired refresh tokens automatically (TTL index).
    await db.refresh_tokens.create_index([("expires_at", ASCENDING)], expireAfterSeconds=0)
    await db.symptom_assessments.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.consents.create_index([("user_id", ASCENDING), ("category", ASCENDING), ("created_at", DESCENDING)])
    await db.notifications.create_index([("user_id", ASCENDING), ("read", ASCENDING), ("created_at", DESCENDING)])
    await db.mental_assessments.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.mood_entries.create_index([("user_id", ASCENDING), ("day", ASCENDING)], unique=True)
    await db.breathing_sessions.create_index([("user_id", ASCENDING)])
    await db.audit_events.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
