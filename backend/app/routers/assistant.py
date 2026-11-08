"""General health chat ("ask anything") with saved conversations.

Safety: emergency words are checked first (no AI); the assistant gives general health
information only, never diagnoses, never names medicines or doses.
"""
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Request, status
from pydantic import BaseModel, Field

from app.ai.prompts import language_rule
from app.ai.safety import EMERGENCY_NUMBERS, check_red_flags
from app.ai.service import AIUnavailableError
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db
from app.repositories.user_repository import to_object_id
from app.routers.assessments import CRISIS_LINES, EMERGENCY_STEPS, SELF_HARM_WORDS, get_ai_service

router = APIRouter(prefix="/assistant", tags=["assistant"])

ASSISTANT_SYSTEM = """You are a friendly health information assistant in a patient-support app in Pakistan.
Rules:
- Answer general health questions clearly and briefly (under 120 words), in plain words.
- You are NOT a doctor: never diagnose, never name a medicine to take, never give doses.
- If the user describes their own symptoms, give general guidance and set suggest_symptom_check to true.
- If anything sounds urgent, tell them to see a doctor today or call 1122.
- Reply as JSON: {"reply": "...", "suggest_symptom_check": true|false, "speech": "..."}
- "speech": if the conversation language is Urdu or Roman Urdu, write the SAME reply in Devanagari
  (Hindi) script, keeping the Urdu words and pronunciation (e.g. "mashwara", "takleef"), because a
  Hindi voice will read it aloud. For English, leave "speech" empty."""

SPEECH_SYSTEM = """Rewrite the given Urdu or Roman Urdu text in Devanagari (Hindi) script so a Hindi
text-to-speech voice pronounces it correctly. Keep the exact Urdu words and meaning; do not translate
them into Sanskrit-style Hindi; do not add or remove anything. Numbers stay as digits.
Reply as JSON: {"speech": "..."}"""

EMERGENCY_REPLY = {
    "en": "This could be an emergency. Please call 1122 now or go to the nearest hospital emergency department.",
    "ur": "یہ ایمرجنسی ہو سکتی ہے۔ ابھی 1122 پر کال کریں یا قریبی ہسپتال کی ایمرجنسی میں جائیں۔",
    "roman_ur": "Yeh emergency ho sakti hai. Abhi 1122 par call karein ya qareebi hospital ki emergency mein jayein.",
}

EMERGENCY_SPEECH = {
    "ur": "यह इमरजेंसी हो सकती है। अभी 1122 पर कॉल करें या क़रीबी हस्पताल की इमरजेंसी में जाएं।",
    "roman_ur": "यह इमरजेंसी हो सकती है। अभी 1122 पर कॉल करें या क़रीबी हस्पताल की इमरजेंसी में जाएं।",
}


class AIChatOutput(BaseModel):
    reply: str = Field(max_length=1500)
    suggest_symptom_check: bool = False
    speech: str = Field(default="", max_length=3000)


class SpeechOutput(BaseModel):
    speech: str = Field(max_length=3000)


class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=1500)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1000)
    language: Literal["en", "ur", "roman_ur"] = "en"
    chat_id: str | None = None


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    text: str
    emergency: bool = False
    at: datetime


class ChatOut(BaseModel):
    chat_id: str
    reply: ChatMessage
    suggest_symptom_check: bool
    emergency_numbers: list[dict] = []
    # Same reply in Devanagari, only for reading aloud with a Hindi voice (Urdu / Roman Urdu chats).
    speech: str = ""


class ChatSummary(BaseModel):
    id: str
    title: str
    language: str
    updated_at: datetime
    messages: int


@router.post("/chat", response_model=ChatOut, dependencies=[limit_by_user("ai_chat", 60, 3600)])
async def chat(body: ChatRequest, request: Request, user: dict = Depends(get_current_user), db=Depends(get_db)):
    now = datetime.now(timezone.utc)
    convo = None
    if body.chat_id:
        oid = to_object_id(body.chat_id)
        convo = await db.assistant_chats.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
        if convo is None:
            raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Chat not found.")
    if convo is None:
        convo = {"user_id": user["_id"], "title": body.message[:60], "language": body.language,
                 "messages": [], "created_at": now, "updated_at": now}
        convo["_id"] = (await db.assistant_chats.insert_one(convo)).inserted_id

    user_msg = {"role": "user", "text": body.message, "emergency": False, "at": now}
    red = check_red_flags(body.message)
    if red:
        self_harm = any(w in red.matched for w in SELF_HARM_WORDS)
        text = " ".join(EMERGENCY_STEPS["self_harm"][body.language][:3]) if self_harm \
            else EMERGENCY_REPLY[body.language]
        reply = {"role": "assistant", "text": text, "emergency": True, "at": now}
        suggest, numbers = False, EMERGENCY_NUMBERS + (CRISIS_LINES if self_harm else [])
        speech = "" if self_harm else EMERGENCY_SPEECH.get(body.language, "")
    else:
        history = "\n".join(f"{m['role']}: {m['text']}" for m in convo["messages"][-10:])
        prompt = (f"Conversation so far:\n{history}\n\n" if history else "") + f"user: {body.message}"
        try:
            result = await get_ai_service(request).generate(
                AIChatOutput, ASSISTANT_SYSTEM + language_rule(body.language), prompt)
        except AIUnavailableError as exc:
            raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_unavailable", exc.message)
        reply = {"role": "assistant", "text": result.data.reply, "emergency": False, "at": now}
        suggest, numbers = result.data.suggest_symptom_check, []
        speech = result.data.speech if body.language != "en" else ""

    await db.assistant_chats.update_one(
        {"_id": convo["_id"]},
        {"$push": {"messages": {"$each": [user_msg, reply]}}, "$set": {"updated_at": now, "language": body.language}},
    )
    return ChatOut(chat_id=str(convo["_id"]), reply=ChatMessage(**reply), suggest_symptom_check=suggest,
                   emergency_numbers=numbers, speech=speech)


@router.post("/speech", dependencies=[limit_by_user("ai_speech", 200, 3600)])
async def to_speech(body: SpeechRequest, request: Request, user: dict = Depends(get_current_user)):
    """Devanagari version of Urdu / Roman Urdu text, so a Hindi voice can read it aloud."""
    try:
        result = await get_ai_service(request).generate(SpeechOutput, SPEECH_SYSTEM, body.text)
    except AIUnavailableError as exc:
        raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_unavailable", exc.message)
    return {"speech": result.data.speech}


class LogItem(BaseModel):
    role: Literal["user", "assistant"]
    text: str = Field(min_length=1, max_length=2000)


class LogRequest(BaseModel):
    chat_id: str | None = None
    language: Literal["en", "ur", "roman_ur"] = "en"
    messages: list[LogItem] = Field(min_length=1, max_length=20)


@router.post("/log")
async def log_messages(body: LogRequest, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Save symptom-check questions/answers that happened inside the chat, so history is complete."""
    now = datetime.now(timezone.utc)
    msgs = [{"role": m.role, "text": m.text, "emergency": False, "at": now} for m in body.messages]
    if body.chat_id:
        oid = to_object_id(body.chat_id)
        res = await db.assistant_chats.update_one(
            {"_id": oid, "user_id": user["_id"]},
            {"$push": {"messages": {"$each": msgs}}, "$set": {"updated_at": now}}) if oid else None
        if res is None or res.matched_count == 0:
            raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Chat not found.")
        return {"chat_id": body.chat_id}
    first = next((m.text for m in body.messages if m.role == "user"), body.messages[0].text)
    doc = {"user_id": user["_id"], "title": first[:60], "language": body.language, "messages": msgs,
           "created_at": now, "updated_at": now}
    return {"chat_id": str((await db.assistant_chats.insert_one(doc)).inserted_id)}


@router.get("/chats", response_model=list[ChatSummary])
async def list_chats(user: dict = Depends(get_current_user), db=Depends(get_db)):
    cursor = db.assistant_chats.find({"user_id": user["_id"]}).sort("updated_at", -1).limit(50)
    return [ChatSummary(id=str(c["_id"]), title=c["title"], language=c.get("language", "en"),
                        updated_at=c["updated_at"], messages=len(c.get("messages", []))) async for c in cursor]


@router.get("/chats/{chat_id}")
async def get_chat(chat_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    oid = to_object_id(chat_id)
    c = await db.assistant_chats.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
    if c is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Chat not found.")
    return {"id": chat_id, "title": c["title"], "language": c.get("language", "en"),
            "messages": [ChatMessage(**m).model_dump() for m in c.get("messages", [])]}
