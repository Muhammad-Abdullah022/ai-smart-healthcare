"""Import the Punjab Healthcare Commission (PHC) registered-labs list into the app's lab data.

Usage (from the backend folder):
    python scripts/import_phc_labs.py <saved file> [more files ...]

The file can be the directory page saved from a browser (Ctrl+S -> .html), a copy-paste into
Excel saved as .xlsx/.csv, or several pages saved one by one. Columns are found by their headers
(name, address, district/city, phone, registration). Output: data/labs/phc_registered_labs.csv,
which the backend loads on its next start. Nothing is guessed: if a city cannot be found in the
address it is left as the district. Prices are NOT in the PHC list (labs are shown as "Ask lab").
"""
import csv
import re
import sys
from datetime import date
from html.parser import HTMLParser
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data" / "labs"
OUT = DATA / "phc_registered_labs.csv"
SOURCE = "https://os.phc.org.pk/Registered_Labs.aspx"
COLS = ["district", "city_or_tehsil", "lab_name", "branch_name", "address", "phone", "lab_type", "test_menu_url",
        "price_list_url", "price_status", "source_url", "source_type", "source_checked_date", "data_status"]


class _Tables(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self._row, self._cell, self._in = [], None, [], False

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._in, self._cell = True, []
        elif tag == "br" and self._in:
            self._cell.append(" ")

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self._row is not None and self._in:
            self._row.append(" ".join("".join(self._cell).split()))
            self._in = False
        elif tag == "tr" and self._row is not None:
            if any(self._row):
                self.rows.append(self._row)
            self._row = None

    def handle_data(self, data):
        if self._in:
            self._cell.append(data)


def read_rows(path: Path) -> list[list[str]]:
    suffix = path.suffix.lower()
    if suffix in (".mhtml", ".mht"):
        # Chrome "Webpage, Single File": the page as shown on screen, including tables built by scripts.
        import email
        msg = email.message_from_bytes(path.read_bytes())
        html = ""
        for part in msg.walk():
            if part.get_content_type() == "text/html":
                html += part.get_payload(decode=True).decode(part.get_content_charset() or "utf-8", "replace")
        p = _Tables()
        p.feed(html)
        return p.rows
    if suffix == ".txt":
        # Copied from the page and pasted into Notepad: columns separated by tabs.
        return [line.split("\t") for line in path.read_text(encoding="utf-8", errors="replace").splitlines()
                if "\t" in line]
    if suffix in (".html", ".htm", ".aspx"):
        p = _Tables()
        p.feed(path.read_text(encoding="utf-8", errors="replace"))
        return p.rows
    if suffix == ".csv":
        with path.open(encoding="utf-8-sig", newline="") as f:
            return [r for r in csv.reader(f)]
    if suffix in (".xlsx", ".xlsm"):
        import openpyxl
        ws = openpyxl.load_workbook(path, read_only=True, data_only=True).active
        return [["" if v is None else str(v).strip() for v in r] for r in ws.iter_rows(values_only=True)]
    raise SystemExit(f"Unsupported file type: {path}")


def find_columns(header: list[str]) -> dict[str, int] | None:
    h = [c.lower() for c in header]

    def col(*words):
        return next((i for i, c in enumerate(h) if any(w in c for w in words)), None)

    cols = {"name": col("name", "laboratory", "lab"), "address": col("address", "location"),
            "district": col("district"), "city": col("city", "tehsil"), "phone": col("phone", "contact", "cell", "mobile"),
            "reg": col("registration", "reg", "license", "licence")}
    return cols if cols["name"] is not None and cols["address"] is not None else None


# Spellings used in addresses -> the city/tehsil names the app uses.
CITY_ALIASES = {"hassanabdal": "Hassan Abdal", "hasan abdal": "Hassan Abdal", "burawala": "Burewala",
                "burewala": "Burewala", "d g khan": "Dera Ghazi Khan", "dg khan": "Dera Ghazi Khan",
                "d.g khan": "Dera Ghazi Khan", "d.g.khan": "Dera Ghazi Khan", "muzaffar garh": "Muzaffargarh",
                "rahimyar khan": "Rahim Yar Khan", "r y khan": "Rahim Yar Khan", "ryk": "Rahim Yar Khan",
                "jehlum": "Jhelum", "bahawal nagar": "Bahawalnagar", "mandi bahaudin": "Mandi Bahauddin",
                "m b din": "Mandi Bahauddin", "sheikhpura": "Sheikhupura", "shiekhupura": "Sheikhupura",
                "t t singh": "Toba Tek Singh", "tt singh": "Toba Tek Singh", "pak pattan": "Pakpattan",
                "kamonke": "Kamoke", "kamoki": "Kamoke", "wah cantt": "Taxila", "arif wala": "Arifwala",
                "chichawatni": "Chichawatni", "mian chanu": "Mian Channu", "taunsa": "Taunsa Sharif",
                "ahmedpur east": "Ahmedpur East", "ahmad pur east": "Ahmedpur East", "muridkay": "Muridke",
                "jaranwala": "Jaranwala", "kot adu": "Kot Addu", "gujar khan": "Gujar Khan"}


def _k(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def clean(text: str) -> str:
    text = re.sub(r"'{2,}", "'", str(text or ""))
    return " ".join(text.split()).strip(" ,")


def find_city(address: str, allowed: list[str]) -> str:
    """A tehsil of the lab's own district named in the address ("Multan Road, Lahore" stays Lahore)."""
    low = " " + re.sub(r"[^a-z0-9]+", " ", address.lower()) + " "
    hits = [city for alias, city in CITY_ALIASES.items()
            if " " + re.sub(r"[^a-z0-9]+", " ", alias).strip() + " " in low]
    hits += [c for c in allowed if " " + c.lower() + " " in low]
    # Ignore "X Road" (a road named after another town) unless the town is also named elsewhere.
    hits = [c for c in hits if c in allowed and not re.search(rf"\b{c.lower()}\s+(road|rd)\b", low.strip())
            or (c in allowed and low.count(" " + c.lower() + " ") > 1)]
    return hits[0] if hits else ""


def district_city(district: str, known: list[str]) -> str:
    alias = CITY_ALIASES.get(district.lower())
    return alias or next((c for c in known if c.lower() == district.lower()), district)


def chain_name(name: str) -> tuple[str, str]:
    """Big chains: use one lab name so chain-wide prices apply; keep the original as the branch."""
    low = name.lower()
    if low.startswith("chughtai"):
        return "Chughtai Lab", name
    if low.startswith("excel lab"):
        return "Excel Labs", name
    if low.startswith("islamabad diagnostic cent"):
        return "Islamabad Diagnostic Centre (IDC)", name
    return name, ""


def main(files: list[str]) -> None:
    known = sorted({r["city_or_tehsil_as_provided"] for r in csv.DictReader(
        (DATA / "all_target_cities_tehsils.csv").open(encoding="utf-8-sig"))}, key=len, reverse=True)
    by_district: dict[str, set[str]] = {}
    for r in csv.DictReader((DATA / "all_target_cities_tehsils.csv").open(encoding="utf-8-sig")):
        by_district.setdefault(_k(r["district_as_provided"]), set()).add(r["city_or_tehsil_as_provided"])
    out, seen = [], set()
    # Labs already in the other data files (same name and city) are not added twice.
    existing = set()
    for other in ("sourced_lab_records_starter.csv", "added_lab_records.csv"):
        if (DATA / other).exists():
            for r in csv.DictReader((DATA / other).open(encoding="utf-8-sig")):
                existing.add((_k(r["lab_name"]), _k(r["city_or_tehsil"])))
    for f in files:
        rows = read_rows(Path(f))
        cols = None
        for r in rows:
            if cols is None:
                cols = find_columns(r)
                if cols is None and len(r) == 4 and str(r[0]).strip().isdigit():
                    # Pasted PHC table without its header row: Sr. | District | Lab name | Address
                    cols = {"name": 2, "address": 3, "district": 1, "city": None, "phone": None, "reg": None}
                else:
                    continue
            if len(r) <= max(i for i in cols.values() if i is not None):
                continue
            get = lambda k: r[cols[k]].strip() if cols[k] is not None and cols[k] < len(r) else ""
            name, address = clean(get("name")), clean(get("address"))
            if not name or name.lower() == "name":
                continue
            district = clean(get("district"))
            home = district_city(district, known)
            allowed = sorted(by_district.get(_k(district), set()) | by_district.get(_k(home), set()) | {home},
                             key=len, reverse=True)
            city = get("city") or find_city(address, allowed) or home
            lab_name, branch = chain_name(name)
            key = (name.lower(), re.sub(r"\W", "", address.lower()))
            if key in seen or (_k(lab_name if branch else name), _k(city)) in existing and not branch:
                continue
            seen.add(key)
            out.append({"district": district, "city_or_tehsil": city, "lab_name": lab_name, "branch_name": branch,
                        "address": address, "phone": get("phone"), "lab_type": "PHC registered",
                        "test_menu_url": "", "price_list_url": "", "price_status": "No public price list verified",
                        "source_url": SOURCE, "source_type": "Punjab Healthcare Commission registered labs directory"
                        + (f" (reg. {get('reg')})" if get("reg") else ""),
                        "source_checked_date": date.today().isoformat(),
                        "data_status": "Registered with PHC; prices not published — ask the lab"})
        if cols is None:
            print(f"{f}: no lab table found in this file (was the list visible when it was saved?)")
    with OUT.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, COLS)
        w.writeheader()
        w.writerows(out)
    no_city = sum(1 for r in out if not r["city_or_tehsil"])
    print(f"Saved {len(out)} labs to {OUT} ({no_city} without a city)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    args = sys.argv[1:]
    # A folder: import every saved page in it.
    if len(args) == 1 and Path(args[0]).is_dir():
        args = [str(p) for p in sorted(Path(args[0]).iterdir())
                if p.suffix.lower() in (".html", ".htm", ".mhtml", ".mht", ".csv", ".xlsx", ".txt")]
    main(args)
