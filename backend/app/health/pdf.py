"""Health record as a PDF, locked (AES-256) with the user's own login password."""
import io
import secrets
from datetime import datetime

from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

INK = colors.HexColor("#0B2B3C")
GREEN = colors.HexColor("#0E9F6E")
MINT = colors.HexColor("#E6F4EF")


def _esc(t) -> str:
    return str(t if t is not None else "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build_pdf(record: dict, risk: dict | None = None) -> bytes:
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm, topMargin=14 * mm,
                            bottomMargin=14 * mm, title="Health Record", author="AI Smart Healthcare")
    ss = getSampleStyleSheet()
    h1 = ParagraphStyle("h1", parent=ss["Title"], textColor=INK, fontSize=20, spaceAfter=2)
    h2 = ParagraphStyle("h2", parent=ss["Heading2"], textColor=colors.white, backColor=INK, borderPadding=(4, 6, 4, 6),
                        fontSize=12, spaceBefore=10, spaceAfter=6)
    body = ParagraphStyle("b", parent=ss["BodyText"], fontSize=9.5, leading=13)
    small = ParagraphStyle("s", parent=body, fontSize=8, textColor=colors.HexColor("#64748B"))
    story = []
    p = record["patient"]
    story += [Paragraph("Personal Health Record", h1),
              Paragraph(f"Generated {datetime.now():%d %b %Y, %I:%M %p} · AI Smart Healthcare app", small), Spacer(1, 6)]

    def table(rows, widths, header=True):
        t = Table(rows, colWidths=widths, repeatRows=1 if header else 0)
        style = [("FONTSIZE", (0, 0), (-1, -1), 8.5), ("VALIGN", (0, 0), (-1, -1), "TOP"),
                 ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#D6E2DE")),
                 ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F8F7")])]
        if header:
            style += [("BACKGROUND", (0, 0), (-1, 0), MINT), ("TEXTCOLOR", (0, 0), (-1, 0), INK),
                      ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold")]
        t.setStyle(TableStyle(style))
        return t

    P = lambda x: Paragraph(_esc(x), body)  # noqa: E731
    info = [["Name", P(p.get("name")), "Age / gender", P(f"{p.get('age') or '—'} / {p.get('gender') or '—'}")],
            ["Blood group", P(p.get("blood_group")), "City", P(p.get("city") or "—")],
            ["Allergies", P(", ".join(p.get("allergies") or []) or "None recorded"),
             "Conditions", P(", ".join(p.get("conditions") or []) or "None recorded")]]
    story += [Paragraph("Patient", h2), table(info, [28 * mm, 60 * mm, 30 * mm, 60 * mm], header=False)]

    if record["vitals"]:
        rows = [["Reading", "Latest value", "Date", "Source"]]
        for v in record["vitals"].values():
            val = f"{v['value']:g}/{v['value2']:g}" if v.get("value2") else f"{v['value']:g}"
            rows.append([v["label"], f"{val} {v['unit']}", v["at"][:10], v["source"]])
        story += [Paragraph("Latest vitals", h2), table(rows, [50 * mm, 45 * mm, 40 * mm, 43 * mm])]

    if risk:
        rows = [["Health risk", "Level", "Main reasons"]]
        for r in risk["risks"]:
            rows.append([r["title"], r["level"].title(), P("; ".join(r["factors"][:3]))])
        story += [Paragraph("Future health risk (estimate)", h2), table(rows, [45 * mm, 22 * mm, 111 * mm])]

    meds = [m for m in record["medicines"] if m["active"]]
    if meds:
        rows = [["Medicine", "Salt", "Times", "Instructions"]]
        for m in meds:
            rows.append([P(f"{m['name']} {m['strength']}"), P(m["salt"]), ", ".join(m["times"]), P(m["instructions"])])
        a = record["adherence_30d"]
        story += [Paragraph("Current medicines", h2), table(rows, [45 * mm, 40 * mm, 30 * mm, 63 * mm]),
                  Paragraph(f"Last 30 days: {a['taken']} doses taken, {a['missed']} missed, {a['skipped']} skipped.", small)]

    if record["reports"]:
        rows = [["Date", "Report", "Out-of-range values", "Summary"]]
        for r in record["reports"][:15]:
            ab = ", ".join(f"{v['name']} {v['value']} {v['unit']} ({v['flag']})" for v in r["abnormal"][:6]) or "All in range"
            rows.append([r["date"][:10], P(r["type"]), P(ab), P(r["summary"][:300])])
        story += [Paragraph("Lab reports", h2), table(rows, [22 * mm, 32 * mm, 56 * mm, 68 * mm])]

    if record["symptom_checks"]:
        rows = [["Date", "Symptoms", "Possible causes", "Urgency / doctor"]]
        for c in record["symptom_checks"][:15]:
            rows.append([c["date"][:10], P(c["symptoms"][:160]), P(", ".join(c["possible_causes"])),
                         P(f"{c['urgency']} · {c['specialist']}")])
        story += [Paragraph("Symptom checks (AI assistant)", h2), table(rows, [22 * mm, 60 * mm, 56 * mm, 40 * mm]),
                  Paragraph("Possible causes are AI suggestions, not diagnoses.", small)]

    if record["prescriptions"]:
        rows = [["Date", "Doctor", "Medicines"]]
        for x in record["prescriptions"][:10]:
            rows.append([x["date"][:10], P(x["doctor"] or "—"), P("<br/>".join(_esc(m) for m in x["medicines"]))])
        story += [Paragraph("Prescriptions (checked by you)", h2), table(rows, [22 * mm, 40 * mm, 116 * mm])]

    if record["history"]:
        rows = [["Type", "Name", "Year / date", "Notes"]]
        for h in record["history"]:
            rows.append([P(h["kind"]), P(h["name"]), P(h["year"]), P(h["notes"][:200])])
        story += [Paragraph("Medical history", h2), table(rows, [32 * mm, 50 * mm, 26 * mm, 70 * mm])]

    if record["mental_health"]:
        rows = [["Date", "Questionnaire", "Score", "Severity"]]
        for m in record["mental_health"]:
            rows.append([m["date"][:10], m["test"], str(m["score"]), m["severity"]])
        story += [Paragraph("Mental wellbeing screening", h2), table(rows, [30 * mm, 50 * mm, 30 * mm, 68 * mm])]

    contacts = p.get("emergency_contacts") or []
    if contacts:
        rows = [["Emergency contact", "Relation", "Phone"]] + [[c.get("name"), c.get("relation", ""), c.get("phone")] for c in contacts]
        story += [Paragraph("Emergency contacts", h2), table(rows, [70 * mm, 50 * mm, 58 * mm])]

    story += [Spacer(1, 10), Paragraph(
        "This record is generated from information saved in the app. AI readings and risk estimates can be wrong; "
        "always confirm with a qualified doctor. In an emergency call 1122.", small)]
    doc.build(story)
    return buf.getvalue()


def lock_pdf(pdf: bytes, password: str) -> bytes:
    """Encrypt with AES-256; opening needs the user's password."""
    writer = PdfWriter(clone_from=PdfReader(io.BytesIO(pdf)))
    writer.encrypt(user_password=password, owner_password=secrets.token_urlsafe(24), algorithm="AES-256")
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()
