"""Standard test names: match the AI's suggested tests to the names labs publish.

Matching is by families (e.g. "Dengue NS1 antigen" and the lab's "DENGUE NS1" are both
"dengue"), so a user sees every dengue test each lab lists, with the lab's own name.
"""
import re

# (key, English name shown to the user, aliases). Specific tests come first.
FAMILIES: list[tuple[str, str, list[str]]] = [
    ("hba1c", "HbA1c (3-month sugar average)", ["hba1c", "glycated", "glycosylated", "a1c"]),
    ("dengue", "Dengue test (NS1 / IgM / IgG)", ["dengue"]),
    ("malaria", "Malaria parasite test (MP)", ["malaria", "malarial", "mp", "malaria parasite"]),
    ("typhoid", "Typhoid test (Typhidot / Widal)", ["typhoid", "typhidot", "widal", "salmonella"]),
    ("cbc", "Complete Blood Count (CBC)", ["cbc", "complete blood count", "blood cp", "full blood count",
                                           "blood count", "hemogram", "haemogram"]),
    ("hb", "Haemoglobin (Hb)", ["hb", "haemoglobin", "hemoglobin"]),
    ("tlc", "Total Leucocyte Count (TLC)", ["tlc", "total leucocyte count", "total leukocyte count", "wbc count"]),
    ("dlc", "Differential Leucocyte Count (DLC)", ["dlc", "differential leucocyte", "differential count"]),
    ("esr", "ESR", ["esr", "erythrocyte sedimentation"]),
    ("crp", "C-Reactive Protein (CRP)", ["crp", "c reactive protein"]),
    ("sugar", "Blood sugar (glucose)", ["bsr", "bsf", "bsl", "fbs", "rbs", "blood sugar", "glucose", "blood glucose"]),
    ("lipid", "Lipid profile (cholesterol)", ["lipid", "cholesterol"]),
    ("lft", "Liver Function Tests (LFT)", ["lft", "lfts", "liver function"]),
    ("rft", "Renal / Kidney Function Tests (RFT)", ["rft", "rfts", "renal function", "kidney function"]),
    ("creatinine", "Serum creatinine", ["creatinine"]),
    ("uric_acid", "Uric acid", ["uric acid"]),
    ("thyroid", "Thyroid tests (TSH / T3 / T4)", ["tsh", "t3", "t4", "thyroid", "free t3", "free t4"]),
    ("urine", "Urine complete examination", ["urine complete", "urine re", "urine routine", "urinalysis",
                                              "urine analysis", "urine dr", "urine test", "urine examination", "urine r e"]),
    ("hcv", "Hepatitis C test (HCV)", ["hcv", "hepatitis c"]),
    ("hbv", "Hepatitis B test (HBsAg)", ["hbv", "hbsag", "hepatitis b"]),
    ("hiv", "HIV test", ["hiv"]),
    ("pregnancy", "Pregnancy test (Beta hCG / UPT)", ["upt", "pregnancy", "beta hcg", "b hcg", "hcg"]),
    ("vit_b12", "Vitamin B12", ["b12"]),
    ("vit_d", "Vitamin D", ["vitamin d", "vit d", "25 oh"]),
    ("ferritin", "Ferritin (iron stores)", ["ferritin"]),
    ("blood_group", "Blood group", ["blood group", "blood grouping", "abo"]),
    ("ana", "ANA", ["ana", "antinuclear"]),
    ("aso", "ASO titre", ["aso"]),
    ("psa", "PSA", ["psa"]),
    ("pt_inr", "Prothrombin time (PT / INR)", ["prothrombin", "inr", "pt with inr"]),
    ("prolactin", "Prolactin", ["prolactin"]),
    ("electrolytes", "Electrolytes (sodium, potassium)", ["electrolytes", "sodium", "potassium"]),
    ("ra_factor", "RA factor (rheumatoid)", ["ra factor", "rheumatoid"]),
    ("urea", "Blood urea", ["urea", "bun"]),
    ("stool", "Stool examination", ["stool routine", "stool examination", "stool re", "stool r e"]),
    ("platelets", "Platelet count", ["platelet", "platelets", "plt"]),
    ("tb", "Tuberculosis test (TB / AFB)", ["tb", "tuberculosis", "afb"]),
]

ENGLISH_NAME = {key: name for key, name, _ in FAMILIES}


def _norm(text: str) -> str:
    return " " + re.sub(r"[^a-z0-9]+", " ", text.lower()).strip() + " "


def family_of(name: str) -> str | None:
    """The test family of a test name, or None if unknown."""
    n = _norm(name)
    if " for dengue patients " in n:
        return None  # special government-capped rate for dengue patients only; not a normal CBC price
    for key, _, aliases in FAMILIES:
        if key == "creatinine" and " ratio " in n:
            continue  # "protein/creatinine ratio" is a different test
        if any(_norm(a) in n for a in aliases):
            return key
    return None
