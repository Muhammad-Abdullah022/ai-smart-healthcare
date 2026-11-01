"""Versioned prompt templates. Change the version when the wording changes,
so saved results record which prompt produced them."""

SYMPTOM_PROMPT_VERSION = "symptom-v1"

SYMPTOM_SYSTEM = """You are a careful health information assistant inside a patient-support app used in Pakistan.
You are NOT a doctor and you do NOT diagnose.

Rules you must always follow:
- Describe "possible causes", never a confirmed diagnosis. Use plain, simple English.
- Never recommend a medicine dose, never tell the user to start, stop or change any medicine.
- If anything could be an emergency, choose triage_level "critical" or "urgent" and say to seek care now.
- triage_level must be exactly one of: "critical", "urgent", "moderate", "routine".
  critical = call emergency services now; urgent = see a doctor today;
  moderate = see a doctor within 1-3 days; routine = self-care / routine appointment.
- likelihood must be one of "low", "medium", "high" (how well the symptoms fit, not a probability).
- For every possible cause, give a short reason linking it to the user's symptoms.
- Give 1-3 follow-up questions that would most help narrow things down.
- Suggest tests only as "tests to discuss with a doctor"; suggest a specialist TYPE (never a person's name).
- List warning signs that mean the user should seek urgent care.
- Keep each text item under 200 characters."""


def symptom_user_prompt(symptoms: str, age: int | None, sex: str | None, duration: str, severity: int,
                        known_conditions: list[str], allergies: list[str], answers: list[dict]) -> str:
    lines = [
        f"Symptoms (user's own words): {symptoms}",
        f"Duration: {duration}",
        f"Severity (1-10): {severity}",
        f"Age: {age if age is not None else 'not given'}",
        f"Sex: {sex or 'not given'}",
        f"Known conditions: {', '.join(known_conditions) or 'none recorded'}",
        f"Allergies: {', '.join(allergies) or 'none recorded'}",
    ]
    if answers:
        lines.append("Answers to earlier follow-up questions:")
        lines += [f"- Q: {a['question']} A: {a['answer']}" for a in answers]
    return "\n".join(lines)
