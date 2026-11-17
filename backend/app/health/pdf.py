"""Health record as a PDF, locked (AES-256) with the user's own login password.

Urdu text (e.g. possible causes from an Urdu chat) is drawn with the bundled DejaVu Sans font, which has
the Urdu letters, after joining the letters (arabic_reshaper) and putting them right-to-left (python-bidi).
"""
import io
import re
import secrets
from datetime import datetime
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.lib import colors
from reportlab.lib.enums import TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

try:  # optional: proper Urdu letter joining and right-to-left order
    import arabic_reshaper
    from bidi.algorithm import get_display
except ImportError:  # pragma: no cover
    arabic_reshaper = None

INK = colors.HexColor("#0B2B3C")
GREEN = colors.HexColor("#0E9F6E")
MINT = colors.HexColor("#E6F4EF")
MUTED = colors.HexColor("#64748B")
RED = colors.HexColor("#DC2626")
AMBER = colors.HexColor("#B45309")
FONT_DIR = Path(__file__).parent / "fonts"
URDU = re.compile(r"[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]")

_fonts_ready = False


def _fonts() -> tuple[str, str]:
    global _fonts_ready
    if not _fonts_ready:
        try:
            pdfmetrics.registerFont(TTFont("Body", str(FONT_DIR / "DejaVuSans.ttf")))
            pdfmetrics.registerFont(TTFont("Body-Bold", str(FONT_DIR / "DejaVuSans-Bold.ttf")))
            _fonts_ready = True
        except Exception:  # pragma: no cover - fall back to built-in fonts
            return "Helvetica", "Helvetica-Bold"
    return "Body", "Body-Bold"


def _esc(t) -> str:
    return str(t if t is not None else "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _ur(text: str) -> str:
    """Urdu script: join letters and order right-to-left so the PDF shows it correctly."""
    if not URDU.search(text) or arabic_reshaper is None:
        return text
    return get_display(arabic_reshaper.reshape(text))


def _split_items(text: str) -> list[str]:
    return [p.strip() for p in re.split(r"[,،]\s*(?![^()]*\))", text) if p.strip()]


def build_pdf(record: dict, risk: dict | None = None) -> bytes:
    regular, bold = _fonts()
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm, topMargin=12 * mm,
                            bottomMargin=14 * mm, title="Health Record", author="AI Smart Healthcare")
    body = ParagraphStyle("b", fontName=regular, fontSize=9, leading=12.5, textColor=colors.HexColor("#1B2B33"))
    body_r = ParagraphStyle("br", parent=body, alignment=TA_RIGHT)
    small = ParagraphStyle("s", parent=body, fontSize=7.8, leading=10, textColor=MUTED)
    h2 = ParagraphStyle("h2", fontName=bold, fontSize=11.5, textColor=colors.white, backColor=INK,
                        borderPadding=(5, 7, 5, 7), spaceBefore=12, spaceAfter=7, leading=14)
    cell_head = ParagraphStyle("ch", parent=body, fontName=bold, textColor=INK, fontSize=8.5)

    def P(x, style=body):
        x = "" if x is None else str(x)
        if URDU.search(x):
            return Paragraph(_esc(_ur(x)), body_r)
        return Paragraph(_esc(x), style)

    def lines(items: list[str]):
        """One item per line (Urdu items right-aligned), so long Urdu text never wraps in the wrong order."""
        if not items:
            return P("—")
        urdu = any(URDU.search(i) for i in items)
        text = "<br/>".join(_esc(_ur(i)) for i in items)
        return Paragraph(text if urdu else "<br/>".join("• " + _esc(i) for i in items), body_r if urdu else body)

    def table(rows, widths, header=True, zebra=True):
        if header:
            rows = [[Paragraph(_esc(c), cell_head) for c in rows[0]], *rows[1:]]
        t = Table(rows, colWidths=widths, repeatRows=1 if header else 0)
        style = [("VALIGN", (0, 0), (-1, -1), "TOP"), ("FONTNAME", (0, 0), (-1, -1), regular),
                 ("FONTSIZE", (0, 0), (-1, -1), 8.5), ("LINEBELOW", (0, 0), (-1, -1), 0.4, colors.HexColor("#E2E8EC")),
                 ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]
        if header:
            style += [("BACKGROUND", (0, 0), (-1, 0), MINT)]
        if zebra:
            style += [("ROWBACKGROUNDS", (0, 1 if header else 0), (-1, -1), [colors.white, colors.HexColor("#F7FAF9")])]
        t.setStyle(TableStyle(style))
        return t

    def badge(level: str):
        level = (level or "").lower()
        col = RED if level in ("urgent", "emergency", "high") else AMBER if level in ("soon", "moderate") else GREEN
        return Paragraph(f'<font color="{col.hexval()}"><b>{_esc(level.title() or "—")}</b></font>', body)

    p = record["patient"]
    story = []
    # Header band
    head = Table([[Paragraph('<font color="white" size="17"><b>Personal Health Record</b></font>', body),
                   Paragraph(f'<font color="white">Generated {datetime.now():%d %b %Y, %I:%M %p}<br/>AI Smart Healthcare</font>',
                             ParagraphStyle("hr", parent=small, alignment=TA_RIGHT, textColor=colors.white))]],
                 colWidths=[110 * mm, 70 * mm])
    head.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), INK), ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                              ("TOPPADDING", (0, 0), (-1, -1), 10), ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
                              ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 10)]))
    story += [head, Spacer(1, 8)]

    info = [[P("Name"), P(p.get("name")), P("Age / gender"), P(f"{p.get('age') or '—'} / {p.get('gender') or '—'}")],
            [P("Blood group"), Paragraph(f'<font color="{RED.hexval()}"><b>{_esc(p.get("blood_group") or "—")}</b></font>', body),
             P("City"), P(p.get("city") or "—")],
            [P("Allergies"), P(", ".join(p.get("allergies") or []) or "None recorded"),
             P("Conditions"), P(", ".join(p.get("conditions") or []) or "None recorded")]]
    t = table(info, [26 * mm, 64 * mm, 26 * mm, 64 * mm], header=False, zebra=False)
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (0, -1), MINT), ("BACKGROUND", (2, 0), (2, -1), MINT),
                           ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#D6E2DE"))]))
    story += [Paragraph("Patient", h2), t]

    if record["vitals"]:
        rows = [["Reading", "Latest value", "Date", "Source"]]
        for v in record["vitals"].values():
            val = f"{v['value']:g}/{v['value2']:g}" if v.get("value2") else f"{v['value']:g}"
            rows.append([P(v["label"]), P(f"{val} {v['unit']}"), P(v["at"][:10]), P(v["source"].title())])
        story += [Paragraph("Latest vitals", h2), table(rows, [50 * mm, 45 * mm, 45 * mm, 40 * mm])]

    if risk:
        rows = [["Health risk", "Level", "Main reasons"]]
        for r in risk["risks"]:
            rows.append([P(r["title"]), badge(r["level"]), lines(r["factors"][:3])])
        story += [Paragraph("Future health risk (estimate)", h2), table(rows, [45 * mm, 24 * mm, 111 * mm])]

    meds = [m for m in record["medicines"] if m["active"]]
    if meds:
        rows = [["Medicine", "Salt", "Times", "Instructions"]]
        for m in meds:
            rows.append([P(f"{m['name']} {m['strength']}"), P(m["salt"] or "—"), P(", ".join(m["times"])),
                         P(m["instructions"] or "—")])
        a = record["adherence_30d"]
        story += [Paragraph("Current medicines", h2), table(rows, [45 * mm, 42 * mm, 30 * mm, 63 * mm]),
                  Spacer(1, 3), Paragraph(f"Last 30 days: {a['taken']} doses taken, {a['missed']} missed, "
                                          f"{a['skipped']} skipped.", small)]

    if record["reports"]:
        rows = [["Date", "Report", "Out-of-range values", "Summary"]]
        for r in record["reports"][:15]:
            ab = [f"{v['name']} {v['value']} {v['unit']} ({v['flag']})" for v in r["abnormal"][:6]]
            rows.append([P(r["date"][:10]), P(r["type"]), lines(ab) if ab else
                         Paragraph(f'<font color="{GREEN.hexval()}">All values in range</font>', body),
                         P(r["summary"][:300])])
        story += [Paragraph("Reports & scans", h2), table(rows, [25 * mm, 33 * mm, 55 * mm, 67 * mm])]

    if record["symptom_checks"]:
        rows = [["Date", "Symptoms", "Possible causes", "Urgency", "Doctor"]]
        for c in record["symptom_checks"][:15]:
            causes = [i for cause in c["possible_causes"] for i in _split_items(cause)]
            doctor = c["specialist"] if c["specialist"] and c["specialist"].lower() != "none" else "—"
            rows.append([P(c["date"][:10]), P(c["symptoms"][:160]), lines(causes[:5]), badge(c["urgency"]), P(doctor)])
        story += [Paragraph("Symptom checks (AI assistant)", h2),
                  table(rows, [25 * mm, 42 * mm, 60 * mm, 21 * mm, 32 * mm]),
                  Spacer(1, 3), Paragraph("Possible causes are AI suggestions, not diagnoses.", small)]

    if record["prescriptions"]:
        rows = [["Date", "Doctor", "Medicines"]]
        for x in record["prescriptions"][:10]:
            rows.append([P(x["date"][:10]), P(x["doctor"] or "—"), lines(x["medicines"])])
        story += [Paragraph("Prescriptions (checked by you)", h2), table(rows, [25 * mm, 40 * mm, 115 * mm])]

    if record["history"]:
        rows = [["Type", "Name", "Year / date", "Notes"]]
        for h in record["history"]:
            rows.append([P(h["kind"]), P(h["name"]), P(h["year"]), P(h["notes"][:200])])
        story += [Paragraph("Medical history", h2), table(rows, [32 * mm, 50 * mm, 26 * mm, 72 * mm])]

    if record["mental_health"]:
        rows = [["Date", "Questionnaire", "Score", "Severity"]]
        for m in record["mental_health"]:
            rows.append([P(m["date"][:10]), P(m["test"]), P(str(m["score"])), P(m["severity"])])
        story += [Paragraph("Mental wellbeing screening", h2), table(rows, [30 * mm, 50 * mm, 30 * mm, 70 * mm])]

    contacts = p.get("emergency_contacts") or []
    if contacts:
        rows = [["Emergency contact", "Relation", "Phone"]] + [[P(c.get("name")), P(c.get("relation", "")), P(c.get("phone"))]
                                                               for c in contacts]
        story += [Paragraph("Emergency contacts", h2), table(rows, [70 * mm, 50 * mm, 60 * mm])]

    story += [Spacer(1, 10), Paragraph(
        "This record is generated from information saved in the app. AI readings and risk estimates can be wrong; "
        "always confirm with a qualified doctor. In an emergency call 1122.", small)]

    def footer(canvas, doc_):
        canvas.saveState()
        canvas.setFont(regular, 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(15 * mm, 8 * mm, f"{p.get('name') or ''} · Personal Health Record")
        canvas.drawRightString(A4[0] - 15 * mm, 8 * mm, f"Page {doc_.page}")
        canvas.restoreState()

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buf.getvalue()


def lock_pdf(pdf: bytes, password: str) -> bytes:
    """Encrypt with AES-256; opening needs the user's password."""
    writer = PdfWriter(clone_from=PdfReader(io.BytesIO(pdf)))
    writer.encrypt(user_password=password, owner_password=secrets.token_urlsafe(24), algorithm="AES-256")
    out = io.BytesIO()
    writer.write(out)
    return out.getvalue()
