"""Login accounts for the DEMO doctor profiles (demo_doctors.csv), so every specialty in every city has
a doctor who can be booked online and who can log in to the doctor panel during the FYP demo.

Only made-up demo profiles get an account — never doctors from the real government list.
All demo accounts share one password that the person running the script types in; it is stored only
as a hash. The payment account shown to patients is clearly marked DEMO.
"""
import re
from datetime import datetime, timezone

EMAIL_DOMAIN = "example.com"  # reserved domain: no real mailbox can receive these
DEMO_PAYMENT = {"payment_method": "JazzCash", "payment_title": "DEMO account - do not send real money",
                "payment_account": "DEMO-0000000"}


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", ".", text.lower()).strip(".")


def demo_email(name: str, city: str) -> str:
    """'Dr. Ahmed Rana', 'Lahore' -> 'ahmed.rana.lahore@example.com'"""
    person = re.sub(r"^(dr|prof)\.?\s+", "", name.strip(), flags=re.IGNORECASE)
    return f"{_slug(person)}.{_slug(city)}@{EMAIL_DOMAIN}"


async def create_demo_doctor_logins(db, password_hash: str) -> tuple[list[dict], int]:
    """Give every demo doctor without a login an approved doctor account. Returns (all logins, newly made)."""
    now = datetime.now(timezone.utc)
    made = 0
    n = 0
    async for d in db.doctors.find({"demo": True, "user_id": {"$exists": False}}):
        n += 1
        base = demo_email(d["name"], d["city"])
        email, i = base, 2
        while await db.users.find_one({"email": email}, {"_id": 1}):
            email = base.replace("@", f"{i}@")
            i += 1
        uid = (await db.users.insert_one({
            "email": email, "password_hash": password_hash, "full_name": d["name"], "roles": ["doctor"],
            "approval": "approved", "demo": True, "email_verified": False, "created_at": now, "last_login": None,
        })).inserted_id
        await db.profiles.insert_one({"user_id": uid, "full_name": d["name"], "city": d["city"],
                                      "gender": d.get("gender") or None, "blood_group": "Unknown", "allergies": [],
                                      "conditions": [], "emergency_contacts": [], "language": "en", "updated_at": now})
        await db.doctors.update_one({"_id": d["_id"]}, {"$set": {
            "user_id": uid, "approved": True, "available": True, "online": True,
            "pmdc_number": f"DEMO-{n:05d}", **DEMO_PAYMENT, "joined_at": now, "updated_at": now}})
        made += 1
    logins = []
    async for d in db.doctors.find({"demo": True, "user_id": {"$exists": True}}).sort([("city", 1), ("specialty", 1)]):
        u = await db.users.find_one({"_id": d["user_id"]}, {"email": 1})
        if u:
            logins.append({"name": d["name"], "specialty": d["specialty"], "city": d["city"], "email": u["email"]})
    return logins, made
