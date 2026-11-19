"""Create login accounts for all DEMO doctor profiles. Run from RUN\\MAKE_DEMO_DOCTOR_LOGINS.bat.

You type the shared demo password (hidden); it is stored only as a hash. The list of emails (no
passwords) is written to Demo_Doctor_Logins.csv in the app folder.
"""
import asyncio
import csv
import getpass
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.core.config import get_settings  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.db.mongo import create_client  # noqa: E402
from app.demo_accounts import create_demo_doctor_logins  # noqa: E402


async def main() -> None:
    while True:
        pw = getpass.getpass("Password for ALL demo doctor accounts (hidden, 8+ letters and numbers): ")
        if len(pw) >= 8 and re.search(r"[A-Za-z]", pw) and re.search(r"\d", pw):
            if getpass.getpass("Type it again: ") == pw:
                break
            print("Passwords do not match.")
        else:
            print("Use at least 8 characters with letters and numbers.")
    settings = get_settings()
    db = create_client(settings.mongodb_uri)[settings.mongodb_db]
    print("Creating accounts ... (this can take a minute)")
    logins, made = await create_demo_doctor_logins(db, hash_password(pw))
    out = ROOT.parent / "Demo_Doctor_Logins.csv"
    with out.open("w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=["name", "specialty", "city", "email"])
        w.writeheader()
        w.writerows(logins)
    print(f"\nDone. {made} new demo doctor accounts ({len(logins)} in total).")
    print(f"Login emails are listed in: {out}")
    print("Example:", logins[0]["email"] if logins else "-")


if __name__ == "__main__":
    asyncio.run(main())
