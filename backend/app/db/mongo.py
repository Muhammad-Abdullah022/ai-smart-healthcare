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
    await db.medicine_records.create_index([("user_id", ASCENDING), ("active", ASCENDING)])
    await db.medication_intake.create_index(
        [("user_id", ASCENDING), ("medicine_id", ASCENDING), ("day", ASCENDING), ("time", ASCENDING)], unique=True)
    await db.sos_events.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.feature_entries.create_index([("user_id", ASCENDING), ("feature", ASCENDING), ("created_at", DESCENDING)])
    await db.medical_reports.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.report_files.create_index([("user_id", ASCENDING)])
    await db.medicine_brands.create_index([("brand_key", ASCENDING)])
    await db.medicine_brands.create_index([("generic_key", ASCENDING)])
    await db.vitals.create_index([("user_id", ASCENDING), ("kind", ASCENDING), ("at", DESCENDING)])
    await db.record_shares.create_index([("token_hash", ASCENDING)])
    await db.record_shares.create_index("expires_at", expireAfterSeconds=0)
    await db.pharmacies.create_index([("city_key", ASCENDING)])
    await db.prescriptions.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.prescription_files.create_index([("user_id", ASCENDING)])
    await db.assistant_chats.create_index([("user_id", ASCENDING), ("updated_at", DESCENDING)])
    await db.labs.create_index([("city_key", ASCENDING)])
    await db.lab_prices.create_index([("city_key", ASCENDING), ("family", ASCENDING)])
    await db.lab_locations.create_index([("city_key", ASCENDING)])
    await db.lab_demo_prices.create_index([("city_key", ASCENDING), ("family", ASCENDING)])
    await db.companion_chats.create_index([("user_id", ASCENDING), ("updated_at", DESCENDING)])
    await db.companion_turns.create_index([("user_id", ASCENDING), ("at", DESCENDING)])
    await db.companion_turns.create_index([("chat_id", ASCENDING), ("at", ASCENDING)])
    await db.companion_memory.create_index([("user_id", ASCENDING)], unique=True)
    await db.doctors.create_index([("city_key", ASCENDING), ("specialty", ASCENDING)])
    await db.appointments.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.audit_events.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
