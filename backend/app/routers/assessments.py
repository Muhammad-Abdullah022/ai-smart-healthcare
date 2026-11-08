"""AI Symptom Checker (feature 1) + Patient Triage (feature 4).

Order of work for every request:
  1. Fixed safety rules look for emergency signs. If found -> emergency answer
     straight away, NO AI call, no extra questions (no delay).
  2. Otherwise the AI service is asked for a structured, validated answer.
  3. Safety post-checks: dosing advice removed; triage can only be raised by rules, never lowered.
  4. Result is saved to the user's own history.
"""
from datetime import datetime, timezone

from bson import ObjectId
from fastapi import APIRouter, Depends, Request, status

from app.ai.prompts import SYMPTOM_PROMPT_VERSION, SYMPTOM_SYSTEM, symptom_user_prompt
from app.ai.safety import DISCLAIMER, EMERGENCY_NUMBERS, check_red_flags, remove_dosing
from app.ai.service import AIService, AIUnavailableError
from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user, get_repo
from app.models.assessment import (
    TRIAGE_ORDER,
    AISymptomOutput,
    AssessmentOut,
    AssessmentSummary,
    Explanation,
    SymptomRequest,
)
from app.repositories.user_repository import UserRepository, to_object_id

router = APIRouter(prefix="/assessments", tags=["assessments"])

LIMITATIONS = (
    "Based only on what you typed. The AI can be wrong, cannot examine you, and has not been "
    "clinically validated. Emergency rules are simple keyword checks and may miss things."
)


def get_ai_service(request: Request) -> AIService:
    # Tests put a fake service on app.state.ai.
    service = getattr(request.app.state, "ai", None)
    return service or AIService.from_settings(get_settings())


def _raise_to(level: str, minimum: str) -> str:
    return level if TRIAGE_ORDER[level] >= TRIAGE_ORDER[minimum] else minimum


def _out(doc: dict) -> AssessmentOut:
    return AssessmentOut(id=str(doc["_id"]), **{k: v for k, v in doc.items() if k not in ("_id", "user_id")})


@router.post("/symptoms", response_model=AssessmentOut, status_code=status.HTTP_201_CREATED,
             dependencies=[limit_by_user("ai_symptoms", 20, 3600)])
async def assess_symptoms(
    body: SymptomRequest,
    user: dict = Depends(get_current_user),
    repo: UserRepository = Depends(get_repo),
    ai: AIService = Depends(get_ai_service),
):
    profile = await repo.get_profile(user["_id"]) or {}
    all_text = " ".join([body.symptoms] + [a.answer for a in body.answers])
    inputs_used = ["symptoms"] + [n for n, v in (("duration", body.duration != "not given"), ("severity", body.severity)) if v] + [
        name for name, value in (("age", body.age), ("sex", body.sex)) if value is not None
    ]
    if profile.get("conditions"):
        inputs_used.append("known conditions (profile)")
    if profile.get("allergies"):
        inputs_used.append("allergies (profile)")
    if body.answers:
        inputs_used.append("follow-up answers")

    red_flag = check_red_flags(all_text)
    doc: dict = {
        "user_id": user["_id"],
        "created_at": datetime.now(timezone.utc),
        "symptoms": body.symptoms,
        "disclaimer": DISCLAIMER,
    }

    if red_flag:
        # 1. Emergency: answer immediately, without AI.
        steps = [
            "Call 1122 now, or go to the nearest hospital emergency department.",
            "Do not drive yourself. Ask someone to take you or wait for the ambulance.",
            "If you are with someone, tell them how you feel right now.",
        ]
        if any(word in red_flag.matched for word in ("suicide", "kill myself", "end my life", "want to die",
                                                     "self harm", "khudkushi", "khud kushi")):
            steps.insert(1, "Please reach out to someone you trust right now. You do not have to face this alone.")
        doc.update(
            emergency=True,
            triage_level=red_flag.level,
            triage_reason=" ".join(red_flag.reasons),
            emergency_numbers=EMERGENCY_NUMBERS,
            next_steps=steps,
            explanation=Explanation(
                method="Emergency safety rules (no AI used)",
                inputs_used=inputs_used,
                rules_triggered=[f'Emergency sign: "{m}"' for m in red_flag.matched],
                ai_provider=None,
                prompt_version=None,
                limitations=LIMITATIONS,
            ).model_dump(),
        )
    else:
        # 2. Ask the AI for a structured answer.
        prompt = symptom_user_prompt(
            body.symptoms, body.age, body.sex, body.duration, body.severity,
            profile.get("conditions", []), profile.get("allergies", []),
            [a.model_dump() for a in body.answers],
        )
        try:
            result = await ai.generate(AISymptomOutput, SYMPTOM_SYSTEM, prompt)
        except AIUnavailableError as exc:
            raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_unavailable", exc.message)
        output: AISymptomOutput = result.data

        # 3. Safety post-checks.
        rules = []
        level = output.triage_level
        if (body.severity or 0) >= 8 and TRIAGE_ORDER[level] < TRIAGE_ORDER["moderate"]:
            level = _raise_to(level, "moderate")
            rules.append("Severity 8 or more: triage raised to at least 'moderate'")
        next_steps = remove_dosing(output.next_steps) or ["Please see a doctor to discuss these symptoms."]
        if len(next_steps) < len(output.next_steps):
            rules.append("Removed AI text that mentioned a medicine dose")

        doc.update(
            emergency=level == "critical",
            triage_level=level,
            triage_reason=output.triage_reason,
            emergency_numbers=EMERGENCY_NUMBERS if level in ("critical", "urgent") else [],
            possible_causes=[c.model_dump() for c in output.possible_causes],
            next_steps=next_steps,
            follow_up_questions=output.follow_up_questions,
            tests_to_discuss=remove_dosing(output.tests_to_discuss),
            specialist_type=output.specialist_type,
            warning_signs=remove_dosing(output.warning_signs),
            explanation=Explanation(
                method="AI assessment with safety rules",
                inputs_used=inputs_used,
                rules_triggered=rules or ["No emergency signs found by the safety rules"],
                ai_provider=result.provider,
                prompt_version=SYMPTOM_PROMPT_VERSION,
                limitations=LIMITATIONS,
            ).model_dump(),
        )

    # 4. Save to the user's history.
    inserted = await repo.db.symptom_assessments.insert_one(doc)
    doc["_id"] = inserted.inserted_id
    await repo.audit(user["_id"], "assessment.create",
                     {"triage_level": doc["triage_level"], "emergency": doc["emergency"]})
    return _out(doc)


@router.get("/symptoms", response_model=list[AssessmentSummary])
async def list_assessments(user: dict = Depends(get_current_user), repo: UserRepository = Depends(get_repo)):
    cursor = repo.db.symptom_assessments.find({"user_id": user["_id"]}).sort("created_at", -1).limit(50)
    return [
        AssessmentSummary(id=str(d["_id"]), created_at=d["created_at"], symptoms=d["symptoms"],
                          triage_level=d["triage_level"], emergency=d["emergency"])
        async for d in cursor
    ]


@router.get("/symptoms/{assessment_id}", response_model=AssessmentOut)
async def get_assessment(assessment_id: str, user: dict = Depends(get_current_user),
                         repo: UserRepository = Depends(get_repo)):
    oid: ObjectId | None = to_object_id(assessment_id)
    # Filter by owner too: another user's id simply returns "not found".
    doc = await repo.db.symptom_assessments.find_one({"_id": oid, "user_id": user["_id"]}) if oid else None
    if doc is None:
        raise ApiError(status.HTTP_404_NOT_FOUND, "not_found", "Assessment not found.")
    return _out(doc)
