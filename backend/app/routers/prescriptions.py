"""Prescription & handwriting reader (feature 26) and schedule from a prescription (feature 34).

The user photographs a prescription; the AI reads (transcribes) what the doctor wrote and explains it in
simple words. Safety:
  * The AI only reads. It never adds a medicine, never changes or suggests a dose.
  * Every medicine line has a confidence; unclear handwriting is marked "not sure", never guessed.
  * Nothing becomes a reminder until the user has checked and confirmed the medicines (status "verified").
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

from app.ai.prompts import language_rule
from app.ai.service import AIUnavailableError
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db
from app.repositories.user_repository import to_object_id
from app.routers.assessments import get_ai_service

router = APIRouter(prefix="/prescriptions", tags=["prescriptions"])

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp", "application/pdf"}
MAX_BYTES = 8 * 1024 * 1024
PROMPT_VERSION = "prescription-v2"
Language = Literal["en", "ur", "roman_ur"]
Confidence = Literal["high", "medium", "low"]

PRESCRIPTION_SYSTEM = """You read doctors' prescriptions (often handwritten, from Pakistan) for a patient-support app.
You are NOT a doctor and you do NOT prescribe. Your job is to READ what is written and explain it simply.

READING RULES
- Go through the prescription line by line from the top. EVERY medicine line becomes one item in "medicines"
  (the first line too) — the summary must not mention a medicine that is missing from the list.
- Transcribe each medicine line exactly as written: brand name, strength, form, dose pattern, timing, duration.
- Pakistani shorthand: "1+0+1" = morning + night, "1+1+1" = three times a day, "0+0+1" = night only,
  "OD" once daily, "BD"/"BID" twice, "TDS"/"TID" three times, "QID" four times, "HS" at bedtime,
  "SOS"/"PRN" only when needed, "AC" before food, "PC" after food, "x 5/7" = for 5 days, "x 2/52" = 2 weeks,
  "Tab" tablet, "Cap" capsule, "Syp" syrup, "Inj" injection, "gtt" drops.
- strength = the medicine's strength (e.g. "500 mg", "250 mg/5 ml"); an amount per dose like "2 tsp"
  belongs in dose_as_written, not in strength.
- If you know the common generic (salt) of a brand sold in Pakistan, put it in generic_name; else "".
- confidence per medicine: "high" only if the name and dose are clearly readable; "medium" if one part is
  uncertain; "low" if the name itself is unclear. Put what is unclear in unclear_parts. NEVER guess a name
  or a number to fill a gap — leave the field "" and say it is unclear.
- Never add a medicine that is not written. Never change, suggest or calculate a dose.
- If the image is not a prescription or is unreadable, set readable=false and explain in summary.

EXPLAINING
- how_to_take: the doctor's instruction in plain words (e.g. "1 tablet in the morning and 1 at night,
  after food"), exactly matching what is written.
- times_per_day: number of doses per day from the written pattern (null if "when needed" or unclear).
- duration_days: number of days if written (null if not written).
- purpose: what this medicine is commonly used for, in general words (e.g. "pain and fever"), or "".
- notes: other things the doctor wrote (diagnosis, tests advised, follow-up date, diet advice).
- warnings: only general safety points (e.g. "complete the full antibiotic course", "ask your pharmacist
  if anything is unclear"). No new medical advice.
- Keep each text item under 200 characters."""


class RxMedicine(BaseModel):
    name: str = Field(default="", max_length=80)
    generic_name: str = Field(default="", max_length=120)
    strength: str = Field(default="", max_length=40)
    form: str = Field(default="", max_length=30)
    dose_as_written: str = Field(default="", max_length=80)
    how_to_take: str = Field(default="", max_length=240)
    times_per_day: int | None = Field(default=None, ge=0, le=8)
    timing: str = Field(default="", max_length=80, description="before/after food, at bedtime, ...")
    duration: str = Field(default="", max_length=60)
    duration_days: int | None = Field(default=None, ge=0, le=365)
    purpose: str = Field(default="", max_length=160)
    confidence: Confidence = "medium"
    unclear_parts: str = Field(default="", max_length=200)


class AIPrescriptionOutput(BaseModel):
    readable: bool = True
    doctor_name: str = Field(default="", max_length=100)
    clinic: str = Field(default="", max_length=140)
    date: str = Field(default="", max_length=30)
    summary: str = Field(max_length=800)
    medicines: list[RxMedicine] = Field(default_factory=list, max_length=20)
    notes: list[str] = Field(default_factory=list, max_length=8)
    warnings: list[str] = Field(default_factory=list, max_length=6)


class PrescriptionOut(BaseModel):
    id: str
    created_at: datetime
    file_name: str
    mime_type: str
    language: str
    status: Literal["needs_review", "verified", "unreadable", "error"]
    reading: AIPrescriptionOutput | None
    confirmed_medicines: list[RxMedicine] = []
    error: str | None = None


class PrescriptionSummary(BaseModel):
    id: str
    created_at: datetime
    status: str
    doctor_name: str
    medicines: list[str]


class ConfirmIn(BaseModel):
    medicines: list[RxMedicine] = Field(min_length=1, max_length=20)
    checked: bool = Field(description="User ticked: 'I checked these against my prescription'")


def _out(d: dict) -> PrescriptionOut:
    return PrescriptionOut(id=str(d["_id"]), created_at=d["created_at"], file_name=d["file_name"],
                           mime_type=d["mime_type"], language=d.get("language", "en"), status=d["status"],
                           reading=d.get("reading"), confirmed_medicines=d.get("confirmed_medicines", []),
                           error=d.get("error"))


async def _owned(db, user, rx_id: str) -> dict:
    oid = to_object_id(rx_id)
    doc = await db.prescriptions.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
    if doc is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Prescription not found.")
    return doc


def _clean(reading: dict) -> dict:
    """Code-side safety: low confidence must say what is unclear; drop empty lines."""
    meds = []
    for m in reading.get("medicines", []):
        if not (m.get("name") or m.get("generic_name") or m.get("dose_as_written")):
            continue
        if not m.get("name"):
            m["confidence"] = "low"
        if m["confidence"] == "low" and not m.get("unclear_parts"):
            m["unclear_parts"] = "Handwriting is not clear — check with your pharmacist."
        meds.append(m)
    reading["medicines"] = meds
    if meds and not any("pharmacist" in w.lower() for w in reading.get("warnings", [])):
        reading["warnings"] = (reading.get("warnings", []) +
                               ["Check every medicine and dose with your pharmacist or doctor before taking it."])[:6]
    return reading


async def _read(ai, db, doc: dict, data: bytes) -> dict:
    try:
        result = await ai.generate(
            AIPrescriptionOutput, PRESCRIPTION_SYSTEM + language_rule(doc.get("language", "en")),
            "Read this prescription and return the JSON. Keep medicine names, strengths and dose patterns "
            "exactly as written (do not translate them).",
            images=[(doc["mime_type"], base64.b64encode(data).decode())],
        )
        reading = _clean(result.data.model_dump())
        state = "needs_review" if reading["readable"] and reading["medicines"] else "unreadable"
        changes = {"reading": reading, "status": state, "error": None, "ai_provider": result.provider,
                   "prompt_version": PROMPT_VERSION}
    except AIUnavailableError as exc:
        changes = {"reading": None, "status": "error", "error": exc.message}
    await db.prescriptions.update_one({"_id": doc["_id"]}, {"$set": changes})
    return {**doc, **changes}


@router.post("", response_model=PrescriptionOut, status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_user("ai_prescriptions", 20, 3600)])
async def upload(request: Request, file: UploadFile = File(...), language: Language = Form("en"),
                 user: dict = Depends(get_current_user), db=Depends(get_db)):
    mime = (file.content_type or "").lower()
    if mime not in ALLOWED_TYPES:
        raise ApiError(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "unsupported_file",
                       "Please upload a photo (JPG/PNG) or a PDF of the prescription.")
    data = await file.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ApiError(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "file_too_large", "The file is larger than 8 MB.")
    if not data:
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "empty_file", "The file is empty.")
    now = datetime.now(timezone.utc)
    file_id = (await db.prescription_files.insert_one({
        "user_id": user["_id"], "data": Binary(data), "mime_type": mime, "size": len(data),
        "sha256": hashlib.sha256(data).hexdigest(), "created_at": now})).inserted_id
    name = re.sub(r"[^\w.\- ]", "_", file.filename or "prescription")[:80]
    doc = {"user_id": user["_id"], "file_id": file_id, "file_name": name, "mime_type": mime, "language": language,
           "created_at": now, "status": "error", "reading": None, "confirmed_medicines": [], "error": None}
    doc["_id"] = (await db.prescriptions.insert_one(doc)).inserted_id
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "prescription.upload", "details": {},
                                      "created_at": now})
    return _out(await _read(get_ai_service(request), db, doc, data))


@router.get("", response_model=list[PrescriptionSummary])
async def list_prescriptions(user: dict = Depends(get_current_user), db=Depends(get_db)):
    out = []
    async for d in db.prescriptions.find({"user_id": user["_id"]}).sort("created_at", -1).limit(100):
        r = d.get("reading") or {}
        meds = d.get("confirmed_medicines") or r.get("medicines", [])
        out.append(PrescriptionSummary(id=str(d["_id"]), created_at=d["created_at"], status=d["status"],
                                       doctor_name=r.get("doctor_name", ""),
                                       medicines=[m.get("name") or m.get("generic_name") or "?" for m in meds]))
    return out


@router.get("/{rx_id}", response_model=PrescriptionOut)
async def get_prescription(rx_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    return _out(await _owned(db, user, rx_id))


@router.post("/{rx_id}/read", response_model=PrescriptionOut,
             dependencies=[limit_by_user("ai_prescriptions", 20, 3600)])
async def read_again(rx_id: str, request: Request, language: Language | None = None,
                     user: dict = Depends(get_current_user), db=Depends(get_db)):
    doc = await _owned(db, user, rx_id)
    if language:
        doc["language"] = language
        await db.prescriptions.update_one({"_id": doc["_id"]}, {"$set": {"language": language}})
    f = await db.prescription_files.find_one({"_id": doc["file_id"], "user_id": user["_id"]})
    return _out(await _read(get_ai_service(request), db, doc, bytes(f["data"])))


@router.put("/{rx_id}/confirm", response_model=PrescriptionOut)
async def confirm(rx_id: str, body: ConfirmIn, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """The user checked (and maybe corrected) the medicines. Only now can reminders be created from it."""
    doc = await _owned(db, user, rx_id)
    if not body.checked:
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "not_checked",
                       "Please tick that you checked the medicines against your prescription.")
    meds = [m.model_dump() for m in body.medicines]
    if any(not m["name"].strip() for m in meds):
        raise ApiError(status.HTTP_422_UNPROCESSABLE_ENTITY, "missing_name",
                       "Every medicine needs a name. Remove a line or ask your pharmacist what it says.")
    for m in meds:
        m["confidence"] = "high"  # confirmed by the user
        m["unclear_parts"] = ""
    await db.prescriptions.update_one({"_id": doc["_id"]}, {"$set": {
        "confirmed_medicines": meds, "status": "verified", "verified_at": datetime.now(timezone.utc)}})
    return _out(await _owned(db, user, rx_id))


@router.get("/{rx_id}/file")
async def prescription_file(rx_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    doc = await _owned(db, user, rx_id)
    f = await db.prescription_files.find_one({"_id": doc["file_id"], "user_id": user["_id"]})
    return Response(content=bytes(f["data"]), media_type=f["mime_type"], headers={"Cache-Control": "private, no-store"})


@router.delete("/{rx_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_prescription(rx_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    doc = await _owned(db, user, rx_id)
    await db.prescription_files.delete_one({"_id": doc["file_id"], "user_id": user["_id"]})
    await db.prescriptions.delete_one({"_id": doc["_id"]})
