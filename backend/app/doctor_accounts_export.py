"""Excel list of all doctor ACCOUNTS (doctors who signed up in the app) for the administrator.

No passwords: the app stores only password hashes, which cannot be turned back into passwords.
A doctor who forgets the password gets a new one from Admin panel -> Doctors -> Reset password.
"""
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

COLUMNS = [("No.", 6), ("Doctor name", 28), ("Specialty", 20), ("City", 14), ("Clinic / hospital", 30),
           ("PMDC no.", 12), ("Login email (Gmail)", 34), ("Gmail?", 8), ("Phone", 15), ("Fee (Rs)", 10),
           ("Payment method", 15), ("Status", 18), ("Signed up", 12), ("Last login", 12)]
STATUS_FILL = {"Approved": "D1FAE5", "Waiting for approval": "FEF3C7", "Rejected": "FEE2E2", "Disabled": "E5E7EB"}


def _date(v) -> str:
    return v.strftime("%d-%m-%Y") if isinstance(v, datetime) else ""


async def doctor_account_rows(db) -> list[dict]:
    rows = []
    async for u in db.users.find({"roles": "doctor"}).sort("created_at", 1):
        d = await db.doctors.find_one({"user_id": u["_id"]}) or {}
        approval = u.get("approval", "approved")
        status = ("Waiting for approval" if approval == "pending" else "Rejected" if approval == "rejected"
                  else "Disabled" if u.get("disabled") else "Approved")
        email = u.get("email", "")
        rows.append({"Doctor name": d.get("name") or u.get("full_name", ""), "Specialty": d.get("specialty", ""),
                     "City": d.get("city", ""), "Clinic / hospital": d.get("clinic", ""),
                     "PMDC no.": d.get("pmdc_number", ""), "Login email (Gmail)": email,
                     "Gmail?": "Yes" if email.lower().endswith(("@gmail.com", "@googlemail.com")) else "No",
                     "Phone": d.get("phone", ""), "Fee (Rs)": d.get("fee_pkr"),
                     "Payment method": d.get("payment_method", ""), "Status": status,
                     "Signed up": _date(u.get("created_at")), "Last login": _date(u.get("last_login"))})
    return rows


def build_workbook(rows: list[dict]) -> Workbook:
    wb = Workbook()
    ws = wb.active
    ws.title = "Doctor accounts"
    ws["A1"] = "AI Smart Healthcare — Doctor accounts"
    ws["A1"].font = Font(bold=True, size=14, color="0B2B3C")
    ws["A2"] = (f"{len(rows)} doctor account(s) · exported {datetime.now():%d-%m-%Y %H:%M} · "
                "Passwords are not listed (stored only as hashes). Reset from Admin panel if forgotten.")
    ws["A2"].font = Font(italic=True, size=9, color="6B7280")
    head = 4
    thin = Side(style="thin", color="D1D5DB")
    for i, (title, width) in enumerate(COLUMNS, 1):
        c = ws.cell(row=head, column=i, value=title)
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="0E9F6E")
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        c.border = Border(top=thin, bottom=thin, left=thin, right=thin)
        ws.column_dimensions[get_column_letter(i)].width = width
    for n, r in enumerate(rows, 1):
        values = [n] + [r[t] for t, _ in COLUMNS[1:]]
        for i, v in enumerate(values, 1):
            c = ws.cell(row=head + n, column=i, value=v)
            c.border = Border(top=thin, bottom=thin, left=thin, right=thin)
            c.alignment = Alignment(vertical="center")
        status_cell = ws.cell(row=head + n, column=[t for t, _ in COLUMNS].index("Status") + 1)
        status_cell.fill = PatternFill("solid", fgColor=STATUS_FILL.get(r["Status"], "FFFFFF"))
    if not rows:
        ws.cell(row=head + 1, column=2, value="No doctor has signed up yet.")
    ws.freeze_panes = ws.cell(row=head + 1, column=3)
    ws.auto_filter.ref = f"A{head}:{get_column_letter(len(COLUMNS))}{head + max(len(rows), 1)}"
    ws.row_dimensions[head].height = 30
    return wb
