"""Make (or promote) the administrator account. Run from RUN\\MAKE_ADMIN.bat.

The password is typed by you (hidden) and stored only as a hash in MongoDB — never in a file.
"""
import asyncio
import getpass
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import get_settings  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.db.mongo import create_client  # noqa: E402
from app.models.user import RegisterRequest  # noqa: E402
from app.repositories.user_repository import UserRepository  # noqa: E402


async def main() -> None:
    settings = get_settings()
    db = create_client(settings.mongodb_uri)[settings.mongodb_db]
    repo = UserRepository(db)
    email = input("Admin email: ").strip().lower()
    user = await repo.find_by_email(email)
    if user:
        print(f"Account found: {user['full_name']}. It will become an administrator.")
    else:
        name = input("Full name: ").strip() or "Administrator"
        while True:
            pw = getpass.getpass("Password (8+ characters, letters and numbers, hidden): ")
            if getpass.getpass("Type it again: ") != pw:
                print("Passwords do not match.")
                continue
            try:
                RegisterRequest(full_name=name, email=email, password=pw, accepted_terms=True)
                break
            except Exception as exc:  # weak password or bad email
                print(str(exc).splitlines()[-1] if str(exc) else exc)
        user = await repo.create_user(email, hash_password(pw), name)
    await db.users.update_one({"_id": user["_id"]}, {"$addToSet": {"roles": "admin"},
                                                     "$set": {"disabled": False}})
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "admin.bootstrap", "details": {},
                                      "created_at": datetime.now(timezone.utc)})
    print(f"\nDone. Log in to the app with {email} to open the Admin panel.")


if __name__ == "__main__":
    asyncio.run(main())
