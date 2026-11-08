"""Medical reports: upload + AI reading (feature 8) and old-vs-new comparison (feature 9).

Files are stored privately in MongoDB (owner-only access). Gemini reads the image/PDF
and returns validated, structured values. The AI never recommends medicines.
"""
import base64
import hashlib
import re
from datetime import datetime, timezone
from typing import Literal

from bson import Binary
from fastapi import APIRouter, Depends, File, Form, Request, UploadFile, status
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app.ai.prompts import REPORT_PROMPT_VERSION, REPORT_SYSTEM, language_rule
from app.ai.service import AIUnavailableError
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db
from app.repositories.user_repository import to_object_id
from app.routers.assessments import get_ai_service

router = APIRouter(prefix="/reports", tags=["reports"])

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "application/pdf"}
MAX_BYTES = 8 * 1024 * 1024
Language = Literal["en", "ur", "roman_ur"]


class ReportValue(BaseModel):
    name: str = Field(max_length=80)
    value: str = Field(max_length=40)
    unit: str = Field(default="", max_length=30)
    reference_range: str = Field(default="", max_length=60)
    flag: Literal["low", "normal", "high", "unknown"] = "unknown"


class AIReportOutput(BaseModel):
    report_type: str = Field(max_length=80)
    report_date: str | None = Field(default=None, max_length=30)
    values: list[ReportValue] = Field(default_factory=list, max_length=80)
    summary: str = Field(max_length=800)
    doctor_type: str = Field(max_length=80)
    urgency: Literal["routine", "soon", "urgent"]
    next_steps: list[str] = Field(default_factory=list, max_length=6)


class ReportOut(BaseModel):
    id: str
    created_at: datetime
    file_name: str
    mime_type: str
    language: str
    analysis: AIReportOutput | None
    error: str | None = None


class ReportSummary(BaseModel):
    id: str
    created_at: datetime
    file_name: str
    report_type: str | None
    report_date: str | None
    urgency: str | None
    abnormal_count: int


def _out(d: dict) -> ReportOut:
    return ReportOut(id=str(d["_id"]), created_at=d["created_at"], file_name=d["file_name"],
                     mime_type=d["mime_type"], language=d.get("language", "en"),
                     analysis=d.get("analysis"), error=d.get("error"))


async def _owned(db, user, report_id: str) -> dict:
    oid = to_object_id(report_id)
    doc = await db.medical_reports.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
    if doc is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Report not found.")
    return doc


async def _analyze(ai, db, doc: dict, data: bytes) -> dict:
    """Ask the AI to read the report. On failure the report stays saved with an error."""
    try:
        result = await ai.generate(
            AIReportOutput, REPORT_SYSTEM + language_rule(doc.get("language", "en")),
            "Read this medical report and return the JSON.",
            images=[(doc["mime_type"], base64.b64encode(data).decode())],
        )
        changes = {"analysis": result.data.model_dump(), "error": None,
                   "ai_provider": result.provider, "prompt_version": REPORT_PROMPT_VERSION}
    except AIUnavailableError as exc:
        changes = {"analysis": None, "error": exc.message}
    await db.medical_reports.update_one({"_id": doc["_id"]}, {"$set": changes})
    return {**doc, **changes}


@router.post("", response_model=ReportOut, status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_user("ai_reports", 15, 3600)])
async def upload_report(request: Request, file: UploadFile = File(...), language: Language = Form("en"),
                        user: dict = Depends(get_current_user), db=Depends(get_db)):
    mime = (file.content_type or "").lower()
    if mime not in ALLOWED_TYPES:
        raise ApiError(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "unsupported_file",
                       "Please upload a photo (JPG/PNG) or a PDF of the report.")
    data = await file.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ApiError(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "file_too_large", "The file is larger than 8 MB.")
    if not data:
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "empty_file", "The file is empty.")
    now = datetime.now(timezone.utc)
    file_id = (await db.report_files.insert_one({"user_id": user["_id"], "data": Binary(data), "mime_type": mime,
                                                 "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                                                 "created_at": now})).inserted_id
    name = re.sub(r"[^\w.\- ]", "_", file.filename or "report")[:80]
    doc = {"user_id": user["_id"], "file_id": file_id, "file_name": name, "mime_type": mime,
           "language": language, "created_at": now, "analysis": None, "error": None}
    doc["_id"] = (await db.medical_reports.insert_one(doc)).inserted_id
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "report.upload", "details": {}, "created_at": now})
    doc = await _analyze(get_ai_service(request), db, doc, data)
    return _out(doc)


@router.get("", response_model=list[ReportSummary])
async def list_reports(user: dict = Depends(get_current_user), db=Depends(get_db)):
    out = []
    async for d in db.medical_reports.find({"user_id": user["_id"]}).sort("created_at", -1).limit(100):
        a = d.get("analysis") or {}
        out.append(ReportSummary(
            id=str(d["_id"]), created_at=d["created_at"], file_name=d["file_name"],
            report_type=a.get("report_type"), report_date=a.get("report_date"), urgency=a.get("urgency"),
            abnormal_count=sum(1 for v in a.get("values", []) if v.get("flag") in ("low", "high")),
        ))
    return out


@router.get("/compare")
async def compare_reports(old: str, new: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Feature 9: match tests by name in two reports and show how each value changed."""
    a, b = await _owned(db, user, old), await _owned(db, user, new)
    if not a.get("analysis") or not b.get("analysis"):
        raise ApiError(status.HTTP_409_CONFLICT, "not_analyzed", "Both reports must be read by the AI first.")

    def key(name: str) -> str:
        return re.sub(r"[^a-z0-9]", "", name.lower())

    def number(v: str) -> float | None:
        m = re.search(r"-?\d+(\.\d+)?", v.replace(",", ""))
        return float(m.group()) if m else None

    old_vals = {key(v["name"]): v for v in a["analysis"]["values"]}
    rows = []
    for v in b["analysis"]["values"]:
        o = old_vals.get(key(v["name"]))
        if not o:
            continue
        on, nn = number(o["value"]), number(v["value"])
        change = "na" if on is None or nn is None else ("up" if nn > on else "down" if nn < on else "same")
        rows.append({"name": v["name"], "unit": v.get("unit", ""), "old_value": o["value"], "new_value": v["value"],
                     "old_flag": o.get("flag", "unknown"), "new_flag": v.get("flag", "unknown"), "change": change,
                     "now_normal": o.get("flag") in ("low", "high") and v.get("flag") == "normal",
                     "now_abnormal": o.get("flag") == "normal" and v.get("flag") in ("low", "high")})
    return {"old": {"id": old, "date": a["analysis"].get("report_date"), "created_at": a["created_at"]},
            "new": {"id": new, "date": b["analysis"].get("report_date"), "created_at": b["created_at"]},
            "rows": rows,
            "note": "Only tests found in both reports are compared. Ask your doctor what the changes mean."}


@router.get("/{report_id}", response_model=ReportOut)
async def get_report(report_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    return _out(await _owned(db, user, report_id))


@router.post("/{report_id}/analyze", response_model=ReportOut, dependencies=[limit_by_user("ai_reports", 15, 3600)])
async def reanalyze(report_id: str, request: Request, user: dict = Depends(get_current_user), db=Depends(get_db)):
    doc = await _owned(db, user, report_id)
    f = await db.report_files.find_one({"_id": doc["file_id"], "user_id": user["_id"]})
    return _out(await _analyze(get_ai_service(request), db, doc, bytes(f["data"])))


@router.get("/{report_id}/file")
async def report_file(report_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    doc = await _owned(db, user, report_id)
    f = await db.report_files.find_one({"_id": doc["file_id"], "user_id": user["_id"]})
    return Response(content=bytes(f["data"]), media_type=f["mime_type"],
                    headers={"Cache-Control": "private, no-store"})
