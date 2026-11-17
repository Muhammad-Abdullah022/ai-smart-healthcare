"""Checks medical report values in code, so "low / normal / high" does not depend on the AI.

The AI only reads (transcribes) the report. For every value we then:
  1. use the reference range printed on the report itself (each lab's own range is the most accurate);
  2. if no range is printed, use the standard adult range below, but only when the unit matches;
  3. mark "critical" values (far outside the range, e.g. potassium 6.8) so the report is shown as urgent.
Ranges are common adult reference values used by Pakistani labs; they are a guide, not a diagnosis.
"""
import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Param:
    key: str
    aliases: tuple[str, ...]
    units: tuple[str, ...]                  # accepted unit spellings (lower-case, no spaces)
    male: tuple[float | None, float | None]
    female: tuple[float | None, float | None]
    critical: tuple[float | None, float | None]  # below / above = critical
    about: str


def _p(key, aliases, units, rng, about, female=None, critical=(None, None)) -> Param:
    return Param(key, tuple(aliases), tuple(units), rng, female or rng, critical, about)


PARAMS: list[Param] = [
    # Complete blood count
    _p("Haemoglobin (Hb)", ["haemoglobin", "hemoglobin", "hb", "hgb"], ["g/dl"], (13.5, 17.5),
       "Oxygen-carrying protein in red blood cells; low means anaemia.", female=(12.0, 15.5), critical=(7.0, 20.0)),
    _p("Total leucocyte count (TLC/WBC)", ["tlc", "wbc", "total leucocyte count", "total leukocyte count", "white blood cells", "white cell count"],
       ["x10^9/l", "10^9/l", "x10^3/ul", "10^3/ul", "x10e9/l", "x10³/µl"], (4.0, 11.0),
       "White blood cells fight infection; high often means infection, low lowers immunity.", critical=(2.0, 30.0)),
    _p("Platelets", ["platelet", "platelets", "plt", "platelet count"], ["x10^9/l", "10^9/l", "x10^3/ul", "10^3/ul", "x10³/µl"], (150, 450),
       "Cells that help blood clot; low in dengue and some infections.", critical=(50, 1000)),
    _p("Red blood cells (RBC)", ["rbc", "red blood cells", "red cell count", "total rbc"], ["x10^12/l", "10^12/l", "x10^6/ul", "10^6/ul", "million/ul"], (4.5, 5.9),
       "Number of red blood cells.", female=(4.0, 5.2)),
    _p("Haematocrit (HCT/PCV)", ["hct", "pcv", "haematocrit", "hematocrit", "packed cell volume"], ["%"], (40, 52),
       "Share of blood made of red cells; rises with dehydration, falls in anaemia.", female=(36, 47)),
    _p("MCV", ["mcv", "mean corpuscular volume", "mean cell volume"], ["fl"], (80, 100),
       "Size of red cells; small in iron deficiency, large in B12/folate deficiency."),
    _p("MCH", ["mch", "mean corpuscular haemoglobin", "mean corpuscular hemoglobin"], ["pg"], (27, 33), "Haemoglobin per red cell."),
    _p("MCHC", ["mchc"], ["g/dl"], (32, 36), "Haemoglobin concentration in red cells."),
    _p("Neutrophils", ["neutrophils", "neutrophil", "polymorphs"], ["%"], (40, 75), "White cells that fight bacterial infection."),
    _p("Lymphocytes", ["lymphocytes", "lymphocyte"], ["%"], (20, 45), "White cells that fight viral infection."),
    _p("Monocytes", ["monocytes", "monocyte"], ["%"], (2, 10), "White cells that clean up infection."),
    _p("Eosinophils", ["eosinophils", "eosinophil"], ["%"], (1, 6), "White cells that rise with allergy and worms."),
    _p("ESR", ["esr", "erythrocyte sedimentation rate"], ["mm/hr", "mm/h", "mm/1sthr", "mm/1st hr"], (0, 15),
       "General sign of inflammation; not specific to one disease.", female=(0, 20)),
    # Sugar
    _p("Fasting blood sugar", ["fasting blood sugar", "fbs", "fasting glucose", "fasting plasma glucose", "glucose fasting", "blood sugar fasting"],
       ["mg/dl"], (70, 99), "Sugar after 8+ hours without food; 100-125 is pre-diabetes, 126+ suggests diabetes.", critical=(54, 400)),
    _p("Random blood sugar", ["random blood sugar", "rbs", "random glucose", "glucose random", "blood sugar random"], ["mg/dl"], (70, 140),
       "Sugar at any time of day; 200+ with symptoms suggests diabetes.", critical=(54, 400)),
    _p("HbA1c", ["hba1c", "glycated haemoglobin", "glycated hemoglobin", "a1c", "glycosylated haemoglobin"], ["%"], (4.0, 5.6),
       "Average sugar over 3 months; 5.7-6.4 pre-diabetes, 6.5+ diabetes."),
    # Kidney
    _p("Serum creatinine", ["creatinine", "serum creatinine", "s. creatinine"], ["mg/dl"], (0.7, 1.3),
       "Waste cleared by the kidneys; high means kidneys may not be working well.", female=(0.5, 1.1), critical=(None, 5.0)),
    _p("Blood urea", ["urea", "blood urea", "serum urea"], ["mg/dl"], (15, 45), "Waste from protein; high with kidney problems or dehydration.", critical=(None, 200)),
    _p("BUN", ["bun", "blood urea nitrogen"], ["mg/dl"], (7, 20), "Urea nitrogen; high with kidney problems or dehydration."),
    _p("Uric acid", ["uric acid", "serum uric acid"], ["mg/dl"], (3.4, 7.0), "High levels can cause gout and kidney stones.", female=(2.4, 6.0)),
    _p("eGFR", ["egfr", "estimated gfr"], ["ml/min/1.73m2", "ml/min/1.73m²", "ml/min"], (90, None),
       "How well the kidneys filter; below 60 for 3 months means chronic kidney disease.", critical=(15, None)),
    # Electrolytes
    _p("Sodium", ["sodium", "na", "serum sodium", "na+"], ["mmol/l", "meq/l"], (135, 145), "Salt balance of the body.", critical=(120, 160)),
    _p("Potassium", ["potassium", "k", "serum potassium", "k+"], ["mmol/l", "meq/l"], (3.5, 5.1), "Important for heart rhythm and muscles.", critical=(2.5, 6.5)),
    _p("Chloride", ["chloride", "cl", "serum chloride", "cl-"], ["mmol/l", "meq/l"], (98, 107), "Salt balance, works with sodium."),
    _p("Calcium", ["calcium", "serum calcium", "total calcium", "ca"], ["mg/dl"], (8.6, 10.3), "Bones, nerves and muscles.", critical=(6.5, 13.0)),
    # Liver
    _p("Total bilirubin", ["bilirubin total", "total bilirubin", "serum bilirubin", "bilirubin"], ["mg/dl"], (0.1, 1.2),
       "Yellow pigment cleared by the liver; high causes jaundice.", critical=(None, 15)),
    _p("Direct bilirubin", ["direct bilirubin", "bilirubin direct", "conjugated bilirubin"], ["mg/dl"], (0.0, 0.3), "Part of bilirubin processed by the liver."),
    _p("Indirect bilirubin", ["indirect bilirubin", "bilirubin indirect", "unconjugated bilirubin"], ["mg/dl"], (0.1, 1.0),
       "Bilirubin not yet processed by the liver; high with red-cell breakdown or Gilbert syndrome."),
    _p("ALT (SGPT)", ["alt", "sgpt", "alanine aminotransferase", "alt (sgpt)", "sgpt (alt)"], ["u/l", "iu/l"], (7, 45),
       "Liver enzyme; high when liver cells are irritated (hepatitis, fatty liver, medicines).", female=(7, 35)),
    _p("AST (SGOT)", ["ast", "sgot", "aspartate aminotransferase", "ast (sgot)", "sgot (ast)"], ["u/l", "iu/l"], (8, 40), "Liver and muscle enzyme."),
    _p("Alkaline phosphatase (ALP)", ["alkaline phosphatase", "alp", "alk phos"], ["u/l", "iu/l"], (44, 147), "Liver and bone enzyme."),
    _p("GGT", ["ggt", "gamma gt", "gamma glutamyl transferase"], ["u/l", "iu/l"], (8, 61), "Liver enzyme; rises with bile blockage and alcohol.", female=(5, 36)),
    _p("Total protein", ["total protein", "serum protein"], ["g/dl"], (6.0, 8.3), "Proteins in blood (albumin + globulin)."),
    _p("Albumin", ["albumin", "serum albumin"], ["g/dl"], (3.5, 5.0), "Main blood protein made by the liver; low in liver/kidney disease or poor nutrition."),
    # Lipids
    _p("Total cholesterol", ["total cholesterol", "cholesterol", "serum cholesterol"], ["mg/dl"], (None, 200),
       "Blood fat; above 200 raises heart risk."),
    _p("Triglycerides", ["triglycerides", "tg", "serum triglycerides"], ["mg/dl"], (None, 150), "Blood fat; high with sugar, oily food, alcohol."),
    _p("HDL cholesterol", ["hdl", "hdl cholesterol", "hdl-c"], ["mg/dl"], (40, None), "\"Good\" cholesterol; higher is better.", female=(50, None)),
    _p("LDL cholesterol", ["ldl", "ldl cholesterol", "ldl-c"], ["mg/dl"], (None, 100), "\"Bad\" cholesterol; lower is better for the heart."),
    # Thyroid
    _p("TSH", ["tsh", "thyroid stimulating hormone"], ["miu/l", "uiu/ml", "µiu/ml", "mu/l"], (0.4, 4.0),
       "Brain's signal to the thyroid; high suggests underactive, low suggests overactive thyroid."),
    _p("Free T4", ["free t4", "ft4", "t4 free"], ["ng/dl"], (0.8, 1.8), "Thyroid hormone."),
    _p("Free T3", ["free t3", "ft3", "t3 free"], ["pg/ml"], (2.3, 4.2), "Active thyroid hormone."),
    # Vitamins / iron / inflammation
    _p("Vitamin D (25-OH)", ["vitamin d", "25-oh vitamin d", "25 hydroxy vitamin d", "vit d", "25(oh)d", "25-hydroxy vitamin d"], ["ng/ml"], (30, 100),
       "Bone and muscle health; below 20 is deficiency, 20-29 insufficiency."),
    _p("Vitamin B12", ["vitamin b12", "b12", "cobalamin", "vit b12"], ["pg/ml"], (200, 900), "Needed for nerves and red cells."),
    _p("Ferritin", ["ferritin", "serum ferritin"], ["ng/ml"], (30, 400), "Iron stores; low means iron deficiency.", female=(15, 150)),
    _p("Serum iron", ["serum iron", "iron"], ["ug/dl", "µg/dl", "mcg/dl"], (60, 170), "Iron in blood."),
    _p("CRP", ["crp", "c-reactive protein", "c reactive protein"], ["mg/l"], (0, 5), "Sign of inflammation or infection."),
    # Urine (numeric parts)
    _p("Urine pus cells", ["pus cells", "urine pus cells", "wbc (urine)", "pus cells/hpf"], ["/hpf"], (0, 5), "White cells in urine; many suggest urine infection."),
    _p("Urine red cells", ["red cells", "urine rbc", "rbc (urine)", "rbcs/hpf"], ["/hpf"], (0, 2), "Blood in urine; needs a doctor's review if raised."),
]

_INDEX: dict[str, Param] = {}
for _param in PARAMS:
    for _a in _param.aliases:
        _INDEX[re.sub(r"[^a-z0-9]", "", _a.lower())] = _param


def find_param(name: str) -> Param | None:
    k = re.sub(r"[^a-z0-9]", "", name.lower())
    if k in _INDEX:
        return _INDEX[k]
    # "Haemoglobin (Hb)" or "S. Creatinine" style names: try the part before a bracket, then each alias inside.
    base = re.sub(r"[^a-z0-9]", "", re.split(r"[(\[]", name.lower())[0])
    if base in _INDEX:
        return _INDEX[base]
    # Longest alias contained in the name wins ("indirect bilirubin" before "direct bilirubin").
    hits = [(len(alias), p) for alias, p in _INDEX.items() if len(alias) >= 5 and alias in k]
    return max(hits, key=lambda h: h[0])[1] if hits else None


def number(text: str) -> float | None:
    m = re.search(r"-?\d+(\.\d+)?", (text or "").replace(",", ""))
    return float(m.group()) if m else None


def parse_range(text: str) -> tuple[float | None, float | None] | None:
    """'13.5 - 17.5', '13.5–17.5', '< 200', 'up to 40', '>= 40', '0-5' -> (low, high)."""
    t = (text or "").lower().replace(",", "").replace("–", "-").replace("—", "-").replace(" to ", "-")
    nums = re.findall(r"\d+(?:\.\d+)?", t)
    if not nums:
        return None
    if re.search(r"(<|less than|up ?to|below|upto)", t) and len(nums) == 1:
        return (None, float(nums[0]))
    if re.search(r"(>|more than|above|greater)", t) and len(nums) == 1:
        return (float(nums[0]), None)
    m = re.search(r"(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)", t)
    if m:
        lo, hi = float(m.group(1)), float(m.group(2))
        return (lo, hi) if lo <= hi else None
    return None


def _unit_ok(unit: str, p: Param) -> bool:
    u = (unit or "").lower().replace(" ", "").replace("μ", "µ")
    return not u or u in p.units


def _fmt(r: tuple[float | None, float | None]) -> str:
    lo, hi = r
    f = lambda x: f"{x:g}"
    return f"{f(lo)} - {f(hi)}" if lo is not None and hi is not None else (f"< {f(hi)}" if hi is not None else f"> {f(lo)}")


def _flag(v: float, r: tuple[float | None, float | None]) -> str:
    lo, hi = r
    if lo is not None and v < lo:
        return "low"
    if hi is not None and v > hi:
        return "high"
    return "normal"


def check_values(values: list[dict], sex: str | None = None) -> list[dict]:
    """Adds flag (computed), flag_source, standard_range, about and critical to each value dict."""
    out = []
    for item in values:
        v = dict(item)
        p = find_param(v.get("name", ""))
        val = number(v.get("value", ""))
        printed = parse_range(v.get("reference_range", ""))
        standard = (p.female if sex == "female" else p.male) if p else None
        v["about"] = p.about if p else ""
        v["standard_range"] = (_fmt(standard) + (f" {p.units[0]}" if p.units else "")) if p else ""
        v["critical"] = False
        if val is None:
            v["flag_source"] = "ai"
        elif printed:
            v["flag"], v["flag_source"] = _flag(val, printed), "report"
        elif p and _unit_ok(v.get("unit", ""), p):
            v["flag"], v["flag_source"] = _flag(val, standard), "standard"
        else:
            v["flag_source"] = "ai"
        if p and val is not None and _unit_ok(v.get("unit", ""), p):
            clo, chi = p.critical
            v["critical"] = (clo is not None and val < clo) or (chi is not None and val > chi)
        out.append(v)
    return out
