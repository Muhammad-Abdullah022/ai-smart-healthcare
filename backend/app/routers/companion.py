"""MindEase-style mental health companion (features 17 and 19).

Flow (adapted from the open-source MindEase project by Asif, rebuilt for this app):
  mood check-in -> affirmation & tips (in the app) -> chat.
Each message goes through one structured AI call that
  1) routes it (feeling / general chat / mental-health question),
  2) reads the emotional state (tone, severity, crisis risk),
  3) writes a reply in the right style for that state.
Long-term memory: every turn is saved; when there are more than 10, the older ones are
summarised by the AI into one private summary (the last 5 stay word-for-word).

Safety: crisis words are checked first without AI; a high AI crisis risk also switches to
the crisis reply with helplines. No diagnosis labels are shown and no medicines are named.
The user can see and delete everything the companion remembers.
"""
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, status
from pydantic import BaseModel, Field

from app.ai.prompts import language_rule
from app.ai.safety import check_red_flags, remove_medicine_sentences
from app.ai.service import AIUnavailableError
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_db
from app.repositories.user_repository import to_object_id
from app.routers.assessments import EMERGENCY_STEPS, SELF_HARM_WORDS, get_ai_service
from app.routers.consents import require_consent

router = APIRouter(prefix="/mental/companion", tags=["mental companion"])

Language = Literal["en", "ur", "roman_ur"]
KEEP_RAW_TURNS = 5
COMPRESS_AFTER = 10

# Extra crisis phrases (English, Roman Urdu, Urdu) on top of the app's red-flag rules.
CRISIS_PHRASES = (
    "don't want to live", "dont want to live", "better off dead", "hurt myself", "harm myself",
    "cut myself", "no reason to live", "can't go on", "cant go on", "tired of living", "wish i was dead",
    "zinda nahi rehna", "jeena nahi chahta", "jeena nahi chahti", "mar jana chahta", "mar jana chahti",
    "khud ko nuqsan", "khatam kar doon", "مرنا چاہتا", "مرنا چاہتی", "خودکشی", "جینا نہیں چاہتا",
)

# Softer warning signs (hopelessness, passive wishes to disappear): the AI reply is kept, but the
# helplines are always added — better one helpline too many than one too few.
WARNING_PHRASES = (
    "sab khatam ho jaye", "sab khatam ho jaaye", "khatam ho jaun", "khatam ho jaon", "gayab ho jaun",
    "kuch matlab nahi", "koi faida nahi", "no point", "pointless", "disappear", "can't take it anymore",
    "cant take it anymore", "give up on everything", "sab chhor doon", "bardasht nahi hota",
    "سب ختم ہو جائے", "غائب ہو جاؤں", "برداشت نہیں ہوتا",
)

CRISIS_LINES = [
    {"name": "Umang Pakistan (24/7, free)", "number": "0317-4288665",
     "note": "24/7 per umang.com.pk; number as listed by MindEase — please confirm"},
    {"name": "Rozan Counseling Helpline (toll-free, Mon–Fri 9:30–5)", "number": "0800-22-444"},
    {"name": "Taskeen (Mon–Sat 11am–11pm)", "number": "+92 316 827 5336"},
    {"name": "Rescue (emergency)", "number": "1122"},
]

UMANG_LINE = {
    "en": "Umang Pakistan listens 24/7 for free: 0317-4288665.",
    "ur": "اُمنگ پاکستان 24 گھنٹے مفت بات سنتا ہے: 0317-4288665۔",
    "roman_ur": "Umang Pakistan 24 ghante muft baat sunta hai: 0317-4288665.",
}

COMPANION_SYSTEM = """You are MindEase, a warm mental-wellbeing companion inside a health app in Pakistan.
You are not a therapist or doctor. Never diagnose, never name a condition as the user's diagnosis,
never name a medicine or dose.

First read the user's message (with the memory and recent conversation) and decide:
- message_type: "emotional" (sharing feelings or a struggle, even subtly), "general" (greeting/small talk),
  or "question" (asking for information about mental health, coping or therapy).
- mental_state: the closest of the listed values ("normal" if nothing stands out).
- severity: mild / moderate / severe / crisis.
- crisis_risk: none / low / medium / high / immediate (thoughts of self-harm or suicide raise this).
- emotional_tone and key_concern (a few words).

Then write "reply" in the style that fits:
- emotional + mild: acknowledge what they said in a specific, personal way; offer one gentle insight or
  reframe; end with a small suggestion or a question. 3-4 sentences.
- emotional + moderate/severe: reflect back what they shared; say the feeling makes sense; offer ONE small,
  concrete coping idea that fits their situation; for severe, gently encourage talking to a counsellor or
  doctor; close warmly, leaving the door open. 4-5 sentences.
- question: answer clearly and accurately in simple words (max 120 words), then one practical tip.
- general: friendly and short, using what you remember about them.
Write flowing, natural sentences like a caring friend who understands psychology: no lists, no headers.
Use the person's name if the memory has it. Do not repeat the same advice you gave recently.
In Urdu and Roman Urdu, speak about yourself with masculine verb forms ("main samajh sakta hoon") so the voice
matches the rest of the app. Hopelessness or wishing everything would end counts as at least "medium" crisis_risk.
"coping_tip": one short, practical tip for right now (or "" for general chat).
"speech": if the reply language is Urdu or Roman Urdu, the same reply in Devanagari (Hindi) script keeping
the Urdu words (it is only read aloud by a Hindi voice); otherwise ""."""

SUMMARY_SYSTEM = """You keep a private memory for a mental-wellbeing companion. Merge the existing summary and
the older conversation turns into ONE updated summary (max 180 words) of what helps personalise future
support: name and basic details the user shared, important people and situations, recurring feelings and
triggers, what helped or did not help, preferences. Plain sentences. Do not invent anything.
Reply as JSON: {"summary": "..."}"""

MentalState = Literal["normal", "stress", "anxiety", "low_mood", "loneliness", "grief", "anger", "sleep",
                      "relationships", "work_study", "trauma", "addiction", "eating", "self_harm", "other"]
Tone = Literal["hopeless", "fearful", "angry", "sad", "numb", "overwhelmed", "confused", "isolated", "ashamed",
               "calm", "hopeful", "neutral"]


class AICompanionOutput(BaseModel):
    message_type: Literal["emotional", "general", "question"]
    mental_state: MentalState = "normal"
    severity: Literal["mild", "moderate", "severe", "crisis"] = "mild"
    crisis_risk: Literal["none", "low", "medium", "high", "immediate"] = "none"
    emotional_tone: Tone = "neutral"
    key_concern: str = Field(default="", max_length=160)
    reply: str = Field(max_length=1500)
    coping_tip: str = Field(default="", max_length=300)
    speech: str = Field(default="", max_length=3000)


class AISummary(BaseModel):
    summary: str = Field(max_length=2000)


class CompanionRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1500)
    language: Language = "en"
    chat_id: str | None = None
    # Mood picked at check-in (only sent with the first message of a chat).
    mood: str | None = Field(default=None, max_length=30)


HELP_NOTE = {
    "en": "If these thoughts get heavy, you can talk to someone any time: Umang Pakistan 0317-4288665 (24/7, free).",
    "ur": "اگر یہ خیالات بھاری ہو جائیں تو آپ کسی بھی وقت بات کر سکتے ہیں: اُمنگ پاکستان 0317-4288665 (24 گھنٹے، مفت)۔",
    "roman_ur": "Agar yeh khayalat bhaari ho jayein to aap kisi bhi waqt baat kar sakte hain: Umang Pakistan "
                "0317-4288665 (24 ghante, muft).",
}


class CompanionReply(BaseModel):
    chat_id: str
    reply: str
    crisis: bool
    # True when helplines are shown with a normal reply (warning signs, not an emergency).
    support_lines: bool = False
    crisis_lines: list[dict] = []
    message_type: str
    tone: str
    severity: str
    coping_tip: str = ""
    speech: str = ""


TONE_SCORE = {"mild": 1, "moderate": 2, "severe": 3, "crisis": 4}


def _is_crisis_text(text: str) -> bool:
    low = text.lower()
    red = check_red_flags(text)
    return any(p in low for p in CRISIS_PHRASES) or bool(red and any(w in red.matched for w in SELF_HARM_WORDS))


def _crisis_reply(language: str) -> str:
    steps = EMERGENCY_STEPS["self_harm"][language]
    return " ".join([steps[1], UMANG_LINE[language], steps[2], steps[0]])


async def _memory_context(db, user_id) -> tuple[str, str]:
    mem = await db.companion_memory.find_one({"user_id": user_id}) or {}
    turns = [t async for t in db.companion_turns.find({"user_id": user_id}).sort("at", -1).limit(KEEP_RAW_TURNS)]
    recent = "\n".join(f"user: {t['user_message']}\ncompanion: {t['reply']}" for t in reversed(turns))
    return mem.get("summary", ""), recent


async def _compress_memory(ai, db, user_id) -> None:
    """Summarise everything except the newest turns into the private memory summary."""
    count = await db.companion_turns.count_documents({"user_id": user_id, "summarised": {"$ne": True}})
    if count <= COMPRESS_AFTER:
        return
    old = [t async for t in db.companion_turns.find({"user_id": user_id, "summarised": {"$ne": True}})
           .sort("at", 1).limit(count - KEEP_RAW_TURNS)]
    mem = await db.companion_memory.find_one({"user_id": user_id}) or {}
    text = "\n".join(f"user: {t['user_message']}\ncompanion: {t['reply']}" for t in old)
    try:
        result = await ai.generate(AISummary, SUMMARY_SYSTEM,
                                   f"Existing summary:\n{mem.get('summary', '(none)')}\n\nOlder turns:\n{text}")
    except AIUnavailableError:
        return  # try again after a later message
    await db.companion_memory.update_one(
        {"user_id": user_id},
        {"$set": {"summary": result.data.summary, "updated_at": datetime.now(timezone.utc)}}, upsert=True)
    # Turns stay in the chat history; they are just no longer sent word-for-word to the AI.
    await db.companion_turns.update_many({"_id": {"$in": [t["_id"] for t in old]}}, {"$set": {"summarised": True}})


@router.post("/chat", response_model=CompanionReply, dependencies=[limit_by_user("ai_companion", 60, 3600)])
async def companion_chat(body: CompanionRequest, request: Request, background: BackgroundTasks,
                         user: dict = Depends(get_current_user), db=Depends(get_db)):
    await require_consent(db, user["_id"], "mental_health")
    now = datetime.now(timezone.utc)
    chat = None
    if body.chat_id:
        oid = to_object_id(body.chat_id)
        chat = await db.companion_chats.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
        if chat is None:
            raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Chat not found.")
    else:
        chat = {"user_id": user["_id"], "title": body.message[:60], "language": body.language, "mood": body.mood,
                "created_at": now, "updated_at": now}
        chat["_id"] = (await db.companion_chats.insert_one(chat)).inserted_id

    ai = get_ai_service(request)
    state = {"message_type": "emotional", "mental_state": "self_harm", "severity": "crisis",
             "crisis_risk": "immediate", "emotional_tone": "hopeless", "key_concern": "", "coping_tip": "",
             "speech": ""}
    warning = False
    if _is_crisis_text(body.message):
        reply, crisis = _crisis_reply(body.language), True
    else:
        summary, recent = await _memory_context(db, user["_id"])
        prompt = (f"Memory about this user:\n{summary or '(nothing yet)'}\n\n"
                  f"Recent conversation:\n{recent or '(none)'}\n\n"
                  + (f"Mood picked at check-in: {body.mood}\n\n" if body.mood else "")
                  + f"New message: {body.message}")
        try:
            result = await ai.generate(AICompanionOutput, COMPANION_SYSTEM + language_rule(body.language), prompt)
        except AIUnavailableError as exc:
            raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_unavailable", exc.message)
        out = result.data
        state = out.model_dump(exclude={"reply"})
        crisis = out.crisis_risk in ("high", "immediate") or out.severity == "crisis"
        low = body.message.lower()
        warning = not crisis and (out.crisis_risk == "medium" or any(p in low for p in WARNING_PHRASES)
                                  or (out.emotional_tone == "hopeless" and out.severity == "severe"))
        if crisis:
            reply = _crisis_reply(body.language)
            state["speech"] = ""
        else:
            reply = remove_medicine_sentences(out.reply) or out.reply
            if reply != out.reply.strip():
                state["speech"] = ""
            state["coping_tip"] = remove_medicine_sentences(out.coping_tip)
            if warning:
                reply = f"{reply} {HELP_NOTE[body.language]}"
                state["speech"] = ""

    await db.companion_turns.insert_one({
        "user_id": user["_id"], "chat_id": chat["_id"], "user_message": body.message, "reply": reply,
        "crisis": crisis, "warning": warning, "message_type": state["message_type"], "mental_state": state["mental_state"],
        "severity": state["severity"], "crisis_risk": state["crisis_risk"], "tone": state["emotional_tone"],
        "key_concern": state["key_concern"], "coping_tip": state["coping_tip"], "language": body.language,
        "at": now, "day": now.date().isoformat(),
    })
    await db.companion_chats.update_one({"_id": chat["_id"]}, {"$set": {"updated_at": now, "language": body.language}})
    if crisis:
        await db.audit_events.insert_one({"user_id": user["_id"], "action": "companion.crisis_shown",
                                          "details": {}, "created_at": now})
    background.add_task(_compress_memory, ai, db, user["_id"])
    return CompanionReply(chat_id=str(chat["_id"]), reply=reply, crisis=crisis, support_lines=warning,
                          crisis_lines=CRISIS_LINES if crisis or warning else [], message_type=state["message_type"],
                          tone=state["emotional_tone"], severity=state["severity"],
                          coping_tip=state["coping_tip"], speech=state["speech"])


@router.get("/chats")
async def list_chats(user: dict = Depends(get_current_user), db=Depends(get_db)):
    cursor = db.companion_chats.find({"user_id": user["_id"]}).sort("updated_at", -1).limit(50)
    return [{"id": str(c["_id"]), "title": c["title"], "language": c.get("language", "en"), "mood": c.get("mood"),
             "updated_at": c["updated_at"]} async for c in cursor]


@router.get("/chats/{chat_id}")
async def get_chat(chat_id: str, user: dict = Depends(get_current_user), db=Depends(get_db)):
    oid = to_object_id(chat_id)
    chat = await db.companion_chats.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
    if chat is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Chat not found.")
    turns = [t async for t in db.companion_turns.find({"chat_id": chat["_id"], "user_id": user["_id"]}).sort("at", 1)]
    return {"id": chat_id, "language": chat.get("language", "en"), "mood": chat.get("mood"),
            "turns": [{"user": t["user_message"], "reply": t["reply"], "crisis": t.get("crisis", False),
                       "coping_tip": t.get("coping_tip", ""), "at": t["at"]} for t in turns]}


@router.get("/memory")
async def get_memory(user: dict = Depends(get_current_user), db=Depends(get_db)):
    """What the companion remembers (shown to the user for transparency)."""
    mem = await db.companion_memory.find_one({"user_id": user["_id"]}) or {}
    turns = await db.companion_turns.count_documents({"user_id": user["_id"]})
    return {"summary": mem.get("summary", ""), "turns": turns, "updated_at": mem.get("updated_at")}


@router.delete("/memory", status_code=status.HTTP_204_NO_CONTENT)
async def forget_me(user: dict = Depends(get_current_user), db=Depends(get_db)):
    """Delete all companion chats, turns and memory for this user."""
    for coll in (db.companion_memory, db.companion_turns, db.companion_chats):
        await coll.delete_many({"user_id": user["_id"]})
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "companion.memory_deleted", "details": {},
                                      "created_at": datetime.now(timezone.utc)})


@router.get("/insights")
async def insights(days: int = Query(default=14, ge=7, le=90), user: dict = Depends(get_current_user),
                   db=Depends(get_db)):
    """Mood trend (check-ins) and how the chats felt, per day — for the wellbeing dashboard."""
    since = (date.today() - timedelta(days=days - 1)).isoformat()
    moods = {m["day"]: m["mood"] async for m in db.mood_entries.find({"user_id": user["_id"], "day": {"$gte": since}})}
    per_day: dict[str, list[int]] = {}
    tones: dict[str, int] = {}
    concerns: dict[str, int] = {}
    async for t in db.companion_turns.find({"user_id": user["_id"], "day": {"$gte": since},
                                            "message_type": "emotional"}):
        per_day.setdefault(t["day"], []).append(TONE_SCORE.get(t.get("severity", "mild"), 1))
        tones[t.get("tone", "neutral")] = tones.get(t.get("tone", "neutral"), 0) + 1
        if t.get("mental_state") not in (None, "normal", "other", "self_harm"):
            concerns[t["mental_state"]] = concerns.get(t["mental_state"], 0) + 1
    days_list = [(date.fromisoformat(since) + timedelta(days=i)).isoformat() for i in range(days)]
    return {
        "days": [{"day": d, "mood": moods.get(d),
                  "chat_heaviness": round(sum(per_day[d]) / len(per_day[d]), 2) if d in per_day else None}
                 for d in days_list],
        "tones": sorted(({"tone": k, "count": v} for k, v in tones.items()), key=lambda x: -x["count"]),
        "themes": sorted(({"theme": k, "count": v} for k, v in concerns.items()), key=lambda x: -x["count"])[:5],
        "note": "Patterns from your check-ins and chats — not a diagnosis.",
    }
