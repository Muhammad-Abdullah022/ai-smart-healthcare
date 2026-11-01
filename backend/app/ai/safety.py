"""Medical safety rules that run BEFORE any AI call.

These are fixed, readable rules (not AI). If an emergency sign is found, the app
shows emergency guidance immediately and does not ask more questions.
The lists are deliberately cautious: a false alarm is safer than a missed emergency.
They are NOT clinically validated and must be reviewed by a medical professional.
"""
import re
from dataclasses import dataclass

EMERGENCY_NUMBERS = [
    {"name": "Rescue / Ambulance", "number": "1122"},
    {"name": "Edhi Ambulance", "number": "115"},
]

# (phrase variants in English and Roman Urdu, human-readable reason, level)
_RED_FLAGS: list[tuple[list[str], str, str]] = [
    (["chest pain", "chest pressure", "chest tightness", "seene mein dard", "seene me dard", "sine me dard",
      "seenay mein dard"], "Chest pain can be a sign of a heart attack.", "critical"),
    (["difficulty breathing", "can't breathe", "cannot breathe", "shortness of breath", "struggling to breathe",
      "saans lene mein takleef", "sans lene me takleef", "saans nahi", "sans nahi aa"],
     "Serious breathing difficulty needs emergency care.", "critical"),
    (["unconscious", "fainted", "passed out", "not waking", "behosh", "be hosh"],
     "Loss of consciousness is an emergency.", "critical"),
    (["seizure", "fits", "convulsion", "dora", "mirgi"], "Seizures need urgent medical help.", "critical"),
    (["face drooping", "slurred speech", "weakness on one side", "one side numb", "sudden confusion",
      "can't speak", "zuban larkhara"], "These can be signs of a stroke.", "critical"),
    (["severe bleeding", "bleeding heavily", "won't stop bleeding", "bohat khoon", "khoon nahi ruk"],
     "Heavy bleeding needs emergency care.", "critical"),
    (["vomiting blood", "coughing blood", "blood in vomit", "khoon ki ulti", "khoon ki ultee"],
     "Vomiting or coughing blood needs urgent care.", "critical"),
    (["swelling of throat", "throat swelling", "tongue swelling", "lips swelling", "anaphylaxis"],
     "Throat or tongue swelling can block breathing (severe allergic reaction).", "critical"),
    (["suicide", "kill myself", "end my life", "want to die", "self harm", "khudkushi", "khud kushi",
      "marna chahta", "marna chahti"], "You deserve support right now.", "critical"),
    (["worst headache", "sudden severe headache", "thunderclap headache"],
     "A sudden, very severe headache needs urgent checking.", "urgent"),
    (["stiff neck and fever", "fever and stiff neck", "neck stiffness"],
     "Fever with a stiff neck can be meningitis.", "urgent"),
    (["pregnant and bleeding", "bleeding during pregnancy", "pregnancy bleeding"],
     "Bleeding in pregnancy needs urgent care.", "urgent"),
    (["poison", "overdose", "swallowed bleach", "zeher"], "Possible poisoning or overdose.", "critical"),
]


@dataclass
class RedFlagResult:
    level: str  # "critical" | "urgent"
    reasons: list[str]
    matched: list[str]


def _normalise(text: str) -> str:
    text = text.lower().replace("’", "'")
    return re.sub(r"\s+", " ", text)


def check_red_flags(text: str) -> RedFlagResult | None:
    """Return a result if the text contains an emergency sign, otherwise None."""
    clean = _normalise(text)
    reasons, matched, level = [], [], None
    for phrases, reason, flag_level in _RED_FLAGS:
        # Whole words only, so "fits" does not match "benefits".
        hit = next((p for p in phrases if re.search(r"(?<!\w)" + re.escape(p) + r"(?!\w)", clean)), None)
        if hit:
            matched.append(hit)
            if reason not in reasons:
                reasons.append(reason)
            if level != "critical":
                level = flag_level
    if not matched:
        return None
    return RedFlagResult(level=level, reasons=reasons, matched=matched)


# Phrases that look like dosing instructions — the app must never give these.
_DOSE_PATTERN = re.compile(r"\b\d+(\.\d+)?\s?(mg|mcg|ml|g|tablets?|tabs?|capsules?|units?)\b", re.IGNORECASE)


def remove_dosing(items: list[str]) -> list[str]:
    """Drop any AI suggestion that contains a medicine dose."""
    return [item for item in items if not _DOSE_PATTERN.search(item)]


DISCLAIMER = (
    "This is health information, not a medical diagnosis. It has not been checked by a doctor. "
    "Please see a qualified doctor for advice. In an emergency call 1122."
)
