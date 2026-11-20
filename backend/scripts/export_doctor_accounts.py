"""Export all doctor accounts to Doctor_Accounts.xlsx in the app folder. Run RUN\\EXPORT_DOCTOR_ACCOUNTS.bat."""
import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.core.config import get_settings  # noqa: E402
from app.db.mongo import create_client  # noqa: E402
from app.doctor_accounts_export import build_workbook, doctor_account_rows  # noqa: E402


async def main() -> None:
    settings = get_settings()
    db = create_client(settings.mongodb_uri)[settings.mongodb_db]
    rows = await doctor_account_rows(db)
    out = ROOT.parent / "Doctor_Accounts.xlsx"
    try:
        build_workbook(rows).save(out)
    except PermissionError:
        print(f"Close {out.name} in Excel first, then run this again.")
        return
    print(f"Done: {len(rows)} doctor account(s) saved to {out}")


if __name__ == "__main__":
    asyncio.run(main())
