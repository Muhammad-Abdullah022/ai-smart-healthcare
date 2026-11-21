"""Shapes for the AI Symptom Checker (feature 1) and Patient Triage (feature 4)."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

TriageLevel = Literal["critical", "urgent", "moderate", "routine"]
# What the patient should do next:
#   self_care   - minor problem: self-care + over-the-counter medicine (ask a pharmacist), no doctor needed
#   tests_first - a few tests decide it: show only the tests; after the report is uploaded the AI decides again
#   see_doctor  - needs a doctor: show matching doctors to book
#   emergency   - call 1122 / go to emergency now
CarePath = Literal["self_care", "tests_first", "see_doctor", "emergency"]
TRIAGE_ORDER = {"routine": 0, "moderate": 1, "urgent": 2, "critical": 3}


class FollowUpAnswer(BaseModel):
    question: str = Field(max_length=300)
    answer: str = Field(max_length=300)


class SymptomRequest(BaseModel):
    symptoms: str = Field(min_length=3, max_length=1000, description="Symptoms in the user's own words")
    # Optional: in the chat flow the AI asks about these in its follow-up questions.
    duration: str = Field(default="not given", min_length=1, max_length=60, description='e.g. "2 days"')
    severity: int | None = Field(default=None, ge=1, le=10)
    age: int | None = Field(default=None, ge=0, le=120)
    sex: Literal["male", "female", "other"] | None = None
    answers: list[FollowUpAnswer] = Field(default_factory=list, max_length=14)
    language: Literal["en", "ur", "roman_ur"] = "en"


# ----- What the AI must return (validated before use) -----

class PossibleCause(BaseModel):
    name: str = Field(max_length=120)
    likelihood: Literal["low", "medium", "high"]
    reason: str = Field(max_length=400)


class OTCOption(BaseModel):
    """An over-the-counter medicine a pharmacist could suggest for relief. Never a dose."""
    name: str = Field(max_length=60)
    helps_with: str = Field(default="", max_length=200)
    avoid_if: str = Field(default="", max_length=240)


class AISymptomOutput(BaseModel):
    ready: bool = True
    possible_causes: list[PossibleCause] = Field(min_length=1, max_length=5)
    triage_level: TriageLevel
    triage_reason: str = Field(max_length=400)
    next_steps: list[str] = Field(min_length=1, max_length=6)
    follow_up_questions: list[str] = Field(default_factory=list, max_length=3)
    tests_to_discuss: list[str] = Field(default_factory=list, max_length=5)
    specialist_type: str | None = Field(default=None, max_length=80)
    warning_signs: list[str] = Field(default_factory=list, max_length=6)
    otc_options: list[OTCOption] = Field(default_factory=list, max_length=4)
    care_path: Literal["self_care", "tests_first", "see_doctor"] = "see_doctor"


class AIReportReview(BaseModel):
    """The AI's decision after reading the test report the symptom check asked for."""
    care_path: Literal["self_care", "see_doctor"]
    summary: str = Field(max_length=500)
    findings: list[str] = Field(default_factory=list, max_length=6)
    likely_cause: str = Field(default="", max_length=120)
    triage_level: TriageLevel = "routine"
    next_steps: list[str] = Field(default_factory=list, max_length=6)
    otc_options: list[OTCOption] = Field(default_factory=list, max_length=4)
    specialist_type: str | None = Field(default=None, max_length=80)
    warning_signs: list[str] = Field(default_factory=list, max_length=6)


class ReportReviewRequest(BaseModel):
    report_id: str


# ----- What the app receives -----

class Explanation(BaseModel):
    """Feature 46: how the result was produced."""
    method: str
    inputs_used: list[str]
    rules_triggered: list[str]
    ai_provider: str | None
    prompt_version: str | None
    limitations: str


class AssessmentOut(BaseModel):
    id: str
    created_at: datetime
    emergency: bool
    # False while the AI still needs answers to its follow-up questions.
    ready: bool = True
    triage_level: TriageLevel
    triage_reason: str
    emergency_numbers: list[dict] = []
    otc_options: list[OTCOption] = []
    possible_causes: list[PossibleCause] = []
    next_steps: list[str] = []
    follow_up_questions: list[str] = []
    tests_to_discuss: list[str] = []
    specialist_type: str | None = None
    warning_signs: list[str] = []
    care_path: CarePath = "see_doctor"
    # Filled after the patient uploads the report asked for in "tests_first".
    report_review: dict | None = None
    symptoms: str
    answers: list[FollowUpAnswer] = []  # the chat: follow-up questions and the user's answers
    explanation: Explanation
    disclaimer: str


class AssessmentSummary(BaseModel):
    id: str
    created_at: datetime
    symptoms: str
    triage_level: TriageLevel
    emergency: bool
