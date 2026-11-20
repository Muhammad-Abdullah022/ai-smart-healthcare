"""Default login accounts for the doctors in the directory (one-time job run by the backend).

Each doctor gets   email: <first.last>@example.com   and the default password the admin chose.
The account must change the password at first login. Until the doctor turns on "Available"
in the doctor panel, patients do not see the doctor as "Online now"; booking requests still reach
the doctor panel. Emails use the reserved example.com domain so no real mailbox (e.g. someone
else's Gmail) receives anything.

How it runs: put backend/_jobs/doctor_logins.json = {"password": "..."} and (re)start the backend.
The job creates the accounts, writes Doctor_Logins.xlsx in the app folder, then deletes the job file.
"""
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

from app.core.security import hash_password, verify_password

DOMAIN = "example.com"
APP_ROOT = Path(__file__).resolve().parents[2]
JOB_FILE = APP_ROOT / "backend" / "_jobs" / "doctor_logins.json"
EXCEL_FILE = APP_ROOT / "Doctor_Logins.xlsx"


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", ".", text.lower()).strip(".")


def login_email(name: str, city: str = "", n: int = 1) -> str:
    person = re.sub(r"^(dr|prof)\.?\s+", "", name.strip(), flags=re.IGNORECASE)
    base = _slug(person) + (f".{_slug(city)}" if city else "")
    return f"{base}{n if n > 1 else ''}@{DOMAIN}"


async def create_default_doctor_logins(db, password: str) -> int:
    """Give every directory doctor without a login an account. Returns how many were made."""
    now = datetime.now(timezone.utc)
    pw_hash = hash_password(password)
    made = 0
    async for d in db.doctors.find({"user_id": {"$exists": False}, "demo": {"$ne": True}}).sort("name", 1):
        email = login_email(d["name"])
        if await db.users.find_one({"email": email}, {"_id": 1}):  # same name: add the city, then a number
            email, n = login_email(d["name"], d["city"]), 2
            while await db.users.find_one({"email": email}, {"_id": 1}):
                email, n = login_email(d["name"], d["city"], n), n + 1
        uid = (await db.users.insert_one({
            "email": email, "password_hash": pw_hash, "full_name": d["name"], "roles": ["doctor"],
            "approval": "approved", "must_change_password": True, "invited": True, "email_verified": False,
            "created_at": now, "last_login": None})).inserted_id
        await db.profiles.insert_one({"user_id": uid, "full_name": d["name"], "city": d["city"], "allergies": [],
                                      "conditions": [], "emergency_contacts": [], "blood_group": "Unknown",
                                      "language": "en", "updated_at": now})
        await db.doctors.update_one({"_id": d["_id"]}, {"$set": {
            "user_id": uid, "approved": True, "available": False, "pmdc_number": d.get("pmdc_number", ""),
            "payment_method": "JazzCash", "payment_title": "", "payment_account": "", "joined_at": now}})
        made += 1
    return made


async def default_login_rows(db, password: str) -> list[dict]:
    rows = []
    checked: dict[str, bool] = {}  # all default accounts share one hash: verify it once, not 500 times
    async for u in db.users.find({"invited": True, "roles": "doctor"}).sort("full_name", 1):
        d = await db.doctors.find_one({"user_id": u["_id"]}) or {}
        h = u["password_hash"]
        if h not in checked:
            checked[h] = verify_password(password, h)
        still_default = bool(u.get("must_change_password")) and checked[h]
        rows.append({"Doctor name": d.get("name") or u["full_name"], "Specialty": d.get("specialty", ""),
                     "City": d.get("city", ""), "Hospital": d.get("clinic", ""), "Login email": u["email"],
                     "Password": password if still_default else "(changed by the doctor)",
                     "Status": "Default password - must change at first login" if still_default else "Active"})
    return rows


def write_excel(rows: list[dict], path: Path = EXCEL_FILE) -> Path:
    wb = Workbook()
    ws = wb.active
    ws.title = "Doctor logins"
    ws["A1"] = "AI Smart Healthcare - Doctor login accounts"
    ws["A1"].font = Font(bold=True, size=14, color="0B2B3C")
    ws["A2"] = (f"{len(rows)} doctors - created {datetime.now():%d-%m-%Y %H:%M}. Each doctor must change the "
                "default password at first login. Keep this file private.")
    ws["A2"].font = Font(italic=True, size=9, color="B45309")
    cols = [("No.", 6), ("Doctor name", 30), ("Specialty", 20), ("City", 15), ("Hospital", 46),
            ("Login email", 40), ("Password", 22), ("Status", 40)]
    thin = Side(style="thin", color="D1D5DB")
    head = 4
    for i, (t, w) in enumerate(cols, 1):
        c = ws.cell(row=head, column=i, value=t)
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="0E9F6E")
        c.alignment = Alignment(horizontal="center", vertical="center")
        c.border = Border(top=thin, bottom=thin, left=thin, right=thin)
        ws.column_dimensions[get_column_letter(i)].width = w
    for n, r in enumerate(rows, 1):
        for i, v in enumerate([n] + [r[t] for t, _ in cols[1:]], 1):
            c = ws.cell(row=head + n, column=i, value=v)
            c.border = Border(top=thin, bottom=thin, left=thin, right=thin)
        if r["Status"] == "Active":
            ws.cell(row=head + n, column=8).fill = PatternFill("solid", fgColor="D1FAE5")
    ws.freeze_panes = ws.cell(row=head + 1, column=3)
    ws.auto_filter.ref = f"A{head}:H{head + max(len(rows), 1)}"
    wb.save(path)
    return path


async def run_doctor_login_job(db, job_file: Path = JOB_FILE, excel_file: Path = EXCEL_FILE) -> None:
    if not job_file.exists():
        return
    try:
        password = json.loads(job_file.read_text(encoding="utf-8"))["password"]
        made = await create_default_doctor_logins(db, password)
        rows = await default_login_rows(db, password)
        write_excel(rows, excel_file)
        print(f"[doctor logins] created {made} accounts; {len(rows)} listed in {excel_file}")
    finally:
        job_file.unlink(missing_ok=True)  # never keep the password on disk
