"""Mental health: crisis support (25), screening (16), mood (24), breathing (22).

Screening uses the standard PHQ-9 (depression) and GAD-7 (anxiety)
questionnaires, scored with their published fixed rules — NOT by AI.
Any answer above 0 on PHQ-9 question 9 (thoughts of self-harm) always shows
crisis support. Saving mental health data requires the user's consent.
"""
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field, model_validator

from app.deps import get_current_user, get_db
from app.routers.consents import require_consent

router = APIRouter(prefix="/mental", tags=["mental health"])

# Source: https://www.therapyroute.com/article/suicide-hotlines-and-crisis-lines-in-pakistan-by-therapyroute
# (numbers checked by the source in August 2026). Re-check before release.
CRISIS_RESOURCES = {
    "checked": "2026-08 (TherapyRoute); re-verify before release",
    "emergency": [
        {"name": "Rescue / Ambulance", "phone": "1122", "hours": "24/7"},
        {"name": "Edhi Ambulance", "phone": "115", "hours": "24/7"},
        {"name": "Police", "phone": "15", "hours": "24/7"},
    ],
    "support": [
        {"name": "Rozan Counseling Helpline (toll-free)", "phone": "0800-22-444",
         "hours": "Mon–Fri 9:30am–5pm"},
        {"name": "Taskeen Health Initiative", "phone": "+92 316 827 5336", "hours": "Mon–Sat 11am–11pm"},
        {"name": "Sehat Tahaffuz (national health helpline)", "phone": "1166", "hours": "Hours not published"},
    ],
    "note": "Pakistan has no 24-hour mental health helpline. If you are in danger right now, call 1122 "
            "or go to the nearest hospital emergency department, and tell someone you trust.",
}

ANSWER_OPTIONS = ["Not at all", "Several days", "More than half the days", "Nearly every day"]

INSTRUMENTS = {
    "phq9": {
        "title": "Mood check (PHQ-9)",
        "intro": "Over the last 2 weeks, how often have you been bothered by any of the following problems?",
        "questions": [
            "Little interest or pleasure in doing things",
            "Feeling down, depressed, or hopeless",
            "Trouble falling or staying asleep, or sleeping too much",
            "Feeling tired or having little energy",
            "Poor appetite or overeating",
            "Feeling bad about yourself — or that you are a failure or have let yourself or your family down",
            "Trouble concentrating on things, such as reading the newspaper or watching television",
            "Moving or speaking so slowly that other people could have noticed, or being so fidgety or "
            "restless that you have been moving around a lot more than usual",
            "Thoughts that you would be better off dead, or of hurting yourself in some way",
        ],
        # (max score, severity label)
        "bands": [(4, "minimal"), (9, "mild"), (14, "moderate"), (19, "moderately severe"), (27, "severe")],
    },
    "gad7": {
        "title": "Anxiety check (GAD-7)",
        "intro": "Over the last 2 weeks, how often have you been bothered by the following problems?",
        "questions": [
            "Feeling nervous, anxious, or on edge",
            "Not being able to stop or control worrying",
            "Worrying too much about different things",
            "Trouble relaxing",
            "Being so restless that it is hard to sit still",
            "Becoming easily annoyed or irritable",
            "Feeling afraid, as if something awful might happen",
        ],
        "bands": [(4, "minimal"), (9, "mild"), (14, "moderate"), (21, "severe")],
    },
}

ADVICE = {
    "minimal": "Your answers suggest few symptoms right now. Keep looking after yourself.",
    "mild": "Your answers suggest mild symptoms. Self-care, rest and talking to someone you trust can help. "
            "Check again in two weeks.",
    "moderate": "Your answers suggest moderate symptoms. Please consider speaking to a doctor or counsellor.",
    "moderately severe": "Your answers suggest significant symptoms. Please speak to a doctor or mental health "
                         "professional soon.",
    "severe": "Your answers suggest severe symptoms. Please speak to a doctor or mental health professional "
              "as soon as possible.",
}

SCREENING_NOTE = ("This questionnaire is a screening tool, not a diagnosis. Only a qualified professional "
                  "can diagnose a mental health condition.")


def score(instrument: str, answers: list[int]) -> tuple[int, str]:
    total = sum(answers)
    for upper, label in INSTRUMENTS[instrument]["bands"]:
        if total <= upper:
            return total, label
    raise ValueError("score out of range")


# ---------- Crisis support (feature 25) ----------

@router.get("/crisis-resources")
async def crisis_resources():
    """Public on purpose: crisis help must never be behind a login."""
    return CRISIS_RESOURCES


# ---------- Screening (feature 16) ----------

class ScreeningRequest(BaseModel):
    instrument: Literal["phq9", "gad7"]
    answers: list[int]

    @model_validator(mode="after")
    def check_answers(self):
        expected = len(INSTRUMENTS[self.instrument]["questions"])
        if len(self.answers) != expected:
            raise ValueError(f"{self.instrument} needs exactly {expected} answers")
        if any(a not in (0, 1, 2, 3) for a in self.answers):
            raise ValueError("each answer must be 0, 1, 2 or 3")
        return self


class ScreeningOut(BaseModel):
    id: str
    instrument: str
    title: str
    score: int
    max_score: int
    severity: str
    advice: str
    crisis: bool
    crisis_resources: dict | None
    note: str
    created_at: datetime


@router.get("/instruments")
async def instruments():
    return {
        key: {"title": v["title"], "intro": v["intro"], "questions": v["questions"], "options": ANSWER_OPTIONS}
        for key, v in INSTRUMENTS.items()
    }


def _screening_out(doc: dict) -> ScreeningOut:
    inst = INSTRUMENTS[doc["instrument"]]
    return ScreeningOut(
        id=str(doc["_id"]), instrument=doc["instrument"], title=inst["title"], score=doc["score"],
        max_score=3 * len(inst["questions"]), severity=doc["severity"], advice=ADVICE[doc["severity"]],
        crisis=doc["crisis"], crisis_resources=CRISIS_RESOURCES if doc["crisis"] else None,
        note=SCREENING_NOTE, created_at=doc["created_at"],
    )


@router.post("/screenings", response_model=ScreeningOut, status_code=status.HTTP_201_CREATED)
async def create_screening(body: ScreeningRequest, user: dict = Depends(get_current_user), db=Depends(get_db)):
    await require_consent(db, user["_id"], "mental_health")
    total, severity = score(body.instrument, body.answers)
    # PHQ-9 question 9 asks about self-harm: any answer above "Not at all" shows crisis support.
    crisis = body.instrument == "phq9" and body.answers[8] > 0
    doc = {"user_id": user["_id"], "instrument": body.instrument, "answers": body.answers, "score": total,
           "severity": severity, "crisis": crisis, "created_at": datetime.now(timezone.utc)}
    doc["_id"] = (await db.mental_assessments.insert_one(doc)).inserted_id
    await db.audit_events.insert_one({"user_id": user["_id"], "action": "mental.screening",
                                      "details": {"instrument": body.instrument, "crisis": crisis},
                                      "created_at": doc["created_at"]})
    return _screening_out(doc)


@router.get("/screenings", response_model=list[ScreeningOut])
async def list_screenings(user: dict = Depends(get_current_user), db=Depends(get_db)):
    cursor = db.mental_assessments.find({"user_id": user["_id"]}).sort("created_at", -1).limit(50)
    return [_screening_out(d) async for d in cursor]


# ---------- Daily mood (feature 24) ----------

class MoodRequest(BaseModel):
    mood: int = Field(ge=1, le=5, description="1 = very bad … 5 = very good")
    note: str = Field(default="", max_length=300)
    day: date | None = None


class MoodOut(BaseModel):
    day: date
    mood: int
    note: str


@router.put("/moods", response_model=MoodOut)
async def save_mood(body: MoodRequest, user: dict = Depends(get_current_user), db=Depends(get_db)):
    """One entry per day: saving again on the same day replaces it."""
    await require_consent(db, user["_id"], "mental_health")
    day = (body.day or datetime.now(timezone.utc).date()).isoformat()
    await db.mood_entries.update_one(
        {"user_id": user["_id"], "day": day},
        {"$set": {"mood": body.mood, "note": body.note, "updated_at": datetime.now(timezone.utc)}},
        upsert=True,
    )
    return MoodOut(day=day, mood=body.mood, note=body.note)


@router.get("/moods", response_model=list[MoodOut])
async def list_moods(days: int = Query(default=30, ge=1, le=365), user: dict = Depends(get_current_user),
                     db=Depends(get_db)):
    since = (datetime.now(timezone.utc).date() - timedelta(days=days - 1)).isoformat()
    cursor = db.mood_entries.find({"user_id": user["_id"], "day": {"$gte": since}}).sort("day", 1)
    return [MoodOut(day=d["day"], mood=d["mood"], note=d.get("note", "")) async for d in cursor]


# ---------- Breathing sessions (feature 22) ----------

class BreathingRequest(BaseModel):
    pattern: Literal["box", "4-7-8", "calm"]
    duration_seconds: int = Field(ge=10, le=3600)


@router.post("/breathing", status_code=status.HTTP_201_CREATED)
async def save_breathing(body: BreathingRequest, user: dict = Depends(get_current_user), db=Depends(get_db)):
    await db.breathing_sessions.insert_one({"user_id": user["_id"], **body.model_dump(),
                                            "completed_at": datetime.now(timezone.utc)})
    return {"saved": True}


@router.get("/breathing/summary")
async def breathing_summary(user: dict = Depends(get_current_user), db=Depends(get_db)):
    sessions = [s async for s in db.breathing_sessions.find({"user_id": user["_id"]})]
    return {"sessions": len(sessions), "total_minutes": round(sum(s["duration_seconds"] for s in sessions) / 60)}


# ---------- Meditation & wellness plan (feature 23) ----------
# A 7-day plan of short guided sessions. The session texts live in the app; the server only keeps which
# sessions were completed, so progress is the same on every device.

PLAN_DAYS = 7
SESSIONS_PER_DAY = 3


class WellnessDone(BaseModel):
    day: int = Field(ge=1, le=PLAN_DAYS)
    session: int = Field(ge=1, le=SESSIONS_PER_DAY)
    minutes: int = Field(default=0, ge=0, le=120)


async def _plan_state(db, user_id) -> dict:
    done = [d async for d in db.wellness_progress.find({"user_id": user_id}).sort("completed_at", 1)]
    keys = sorted({(d["day"], d["session"]) for d in done})
    today = next((day for day in range(1, PLAN_DAYS + 1)
                  if any((day, s) not in keys for s in range(1, SESSIONS_PER_DAY + 1))), PLAN_DAYS)
    day_done_today = any(d["completed_at"].date() == datetime.now(timezone.utc).date() for d in done
                         if isinstance(d.get("completed_at"), datetime))
    return {"completed": [{"day": d, "session": s} for d, s in keys],
            "current_day": today, "finished": len(keys) >= PLAN_DAYS * SESSIONS_PER_DAY,
            "total_minutes": sum(d.get("minutes", 0) for d in done), "practised_today": day_done_today,
            "days": PLAN_DAYS, "sessions_per_day": SESSIONS_PER_DAY}


@router.get("/wellness-plan")
async def wellness_plan(user: dict = Depends(get_current_user), db=Depends(get_db)):
    return await _plan_state(db, user["_id"])


@router.post("/wellness-plan/complete")
async def wellness_complete(body: WellnessDone, user: dict = Depends(get_current_user), db=Depends(get_db)):
    await db.wellness_progress.update_one(
        {"user_id": user["_id"], "day": body.day, "session": body.session},
        {"$set": {"minutes": body.minutes, "completed_at": datetime.now(timezone.utc)}}, upsert=True)
    return await _plan_state(db, user["_id"])


@router.delete("/wellness-plan")
async def wellness_restart(user: dict = Depends(get_current_user), db=Depends(get_db)):
    await db.wellness_progress.delete_many({"user_id": user["_id"]})
    return await _plan_state(db, user["_id"])
