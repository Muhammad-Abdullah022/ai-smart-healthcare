"""Future health risk (feature 40) with personalised recommendations (feature 45).

Calculated in code (no AI), so every result can be explained factor by factor:
  * Type 2 diabetes — Indian Diabetes Risk Score (IDRS, Mohan et al. 2005), made for South Asians:
    age + waist + physical activity + family history (0–100; >=60 high, 30–50 moderate).
    If the user already has diabetes, it shows control instead (HbA1c / sugar readings).
  * Heart disease — count of major risk factors (age, smoking, BP, diabetes, cholesterol, obesity,
    family history, inactivity). A screening count, not a validated 10-year percentage.
  * High blood pressure — latest readings classified with the ACC/AHA 2017 categories.
  * Weight — BMI with the WHO Asian cut-offs (23 overweight, 27.5 obese).
  * Kidney — diabetes/BP plus creatinine / eGFR from reports.
  * Anaemia — latest haemoglobin from reports.
These are estimates to talk about with a doctor, not a diagnosis.
"""
import re

from app.ai.lab_ranges import find_param, number

LEVELS = ["low", "moderate", "high"]


def _lab_latest(reports: list[dict]) -> dict[str, float]:
    """Latest numeric value of each known lab test from analysed reports (newest first in the list)."""
    out: dict[str, float] = {}
    for r in reports:
        for v in (r.get("analysis") or {}).get("values", []):
            p = find_param(v.get("name", ""))
            val = number(v.get("value", ""))
            if p and val is not None and p.key not in out:
                out[p.key] = val
    return out


def _has(items: list[str], *words: str) -> bool:
    text = " ".join(items).lower()
    return any(re.search(rf"\b{w}", text) for w in words)


def assess(profile: dict, age: int | None, vitals: dict, reports: list[dict]) -> dict:
    life = profile.get("lifestyle") or {}
    sex = profile.get("gender")
    conditions = [c.lower() for c in profile.get("conditions", [])]
    family = [f.lower() for f in life.get("family_history", [])]
    labs = _lab_latest(reports)
    smoker = bool(life.get("smoker"))
    activity = life.get("activity", "")  # "active", "some", "inactive"
    waist = life.get("waist_cm")
    height = life.get("height_cm")
    weight = (vitals.get("weight") or {}).get("value") or life.get("weight_kg")
    bmi = round(weight / ((height / 100) ** 2), 1) if weight and height else None
    bp = vitals.get("bp")
    sys_bp, dia_bp = (bp["value"], bp.get("value2")) if bp else (None, None)
    has_diabetes = _has(conditions, "diabet", "sugar")
    has_htn = _has(conditions, "hypertension", "blood pressure", "bp")
    missing = []

    risks = []

    # ---- Type 2 diabetes ----
    if has_diabetes:
        a1c = labs.get("HbA1c")
        level = "high" if a1c and a1c >= 8 else "moderate" if not a1c or a1c >= 7 else "low"
        risks.append({
            "key": "diabetes", "title": "Diabetes control", "level": level, "score": a1c, "score_label": "HbA1c %" if a1c else "",
            "factors": ["You have diabetes"] + ([f"Latest HbA1c {a1c}% (target usually below 7%)"] if a1c else ["No HbA1c in your reports yet"]),
            "tips": ["Check HbA1c every 3 months", "Walk 30 minutes daily", "Less sugar, white flour and sweet drinks",
                     "Yearly eye, kidney (urine albumin) and foot check"],
        })
    else:
        score, factors = 0, []
        if age is None:
            missing.append("date of birth")
        elif age >= 50:
            score += 30; factors.append(f"Age {age} (50 or more): +30")
        elif age >= 35:
            score += 20; factors.append(f"Age {age} (35–49): +20")
        if waist:
            limit_hi, limit_mid = (90, 80) if sex == "female" else (100, 90)
            if waist >= limit_hi:
                score += 20; factors.append(f"Waist {waist} cm: +20")
            elif waist >= limit_mid:
                score += 10; factors.append(f"Waist {waist} cm: +10")
        else:
            missing.append("waist size")
        if activity == "inactive":
            score += 30; factors.append("Little physical activity: +30")
        elif activity == "some":
            score += 20; factors.append("Some physical activity: +20")
        elif not activity:
            missing.append("exercise")
        parents = sum(1 for f in family if "diabet" in f)
        if life.get("diabetes_parents") == "both" or parents >= 2:
            score += 20; factors.append("Both parents have diabetes: +20")
        elif life.get("diabetes_parents") == "one" or parents == 1:
            score += 10; factors.append("One parent has diabetes: +10")
        fbs, a1c = labs.get("Fasting blood sugar"), labs.get("HbA1c")
        prediabetes = (fbs and fbs >= 100) or (a1c and a1c >= 5.7)
        level = "high" if score >= 60 or prediabetes else "moderate" if score >= 30 else "low"
        if prediabetes:
            factors.append("A sugar test in your reports is already above normal")
        risks.append({
            "key": "diabetes", "title": "Type 2 diabetes", "level": level, "score": score, "score_label": "IDRS (0–100)",
            "factors": factors or ["No risk factors found yet"],
            "tips": (["Get a fasting sugar or HbA1c test this month"] if level != "low" else ["Check sugar every 1–3 years after age 35"])
                    + ["Walk at least 30 minutes, 5 days a week", "Keep waist below 90 cm (men) / 80 cm (women)",
                       "Fewer sweet drinks, white rice and refined flour"],
        })

    # ---- High blood pressure ----
    if sys_bp:
        if sys_bp >= 180 or (dia_bp and dia_bp >= 120):
            cat, level = "Very high (hypertensive crisis)", "high"
        elif sys_bp >= 140 or (dia_bp and dia_bp >= 90):
            cat, level = "Stage 2 high", "high"
        elif sys_bp >= 130 or (dia_bp and dia_bp >= 80):
            cat, level = "Stage 1 high", "moderate"
        elif sys_bp >= 120:
            cat, level = "Elevated", "moderate"
        else:
            cat, level = "Normal", "low"
        bp_factors = [f"Latest reading {int(sys_bp)}/{int(dia_bp or 0)} mmHg: {cat}"]
    else:
        level, bp_factors = ("moderate" if has_htn else "low"), ["No blood pressure reading yet — add one in Health Trends"]
        missing.append("blood pressure reading")
    if has_htn:
        bp_factors.insert(0, "You have high blood pressure")
    tips = ["Less salt (under 1 teaspoon a day), fewer pickles and salty snacks", "Walk daily and keep a healthy weight",
            "Check BP at home and note the readings"]
    if sys_bp and (sys_bp >= 180 or (dia_bp and dia_bp >= 120)):
        tips.insert(0, "Very high reading: rest 5 minutes and re-check; with chest pain, breathlessness or weakness call 1122")
    risks.append({"key": "bp", "title": "High blood pressure", "level": level,
                  "score": sys_bp, "score_label": "Top number (mmHg)" if sys_bp else "", "factors": bp_factors, "tips": tips})

    # ---- Heart disease ----
    hf = []
    if age and ((sex == "female" and age >= 55) or (sex != "female" and age >= 45)):
        hf.append(f"Age {age}")
    if smoker:
        hf.append("Smoking")
    if has_htn or (sys_bp and sys_bp >= 140):
        hf.append("High blood pressure")
    if has_diabetes or (labs.get("HbA1c") or 0) >= 6.5:
        hf.append("Diabetes")
    tc, ldl, hdl = labs.get("Total cholesterol"), labs.get("LDL cholesterol"), labs.get("HDL cholesterol")
    if (tc and tc >= 240) or (ldl and ldl >= 160):
        hf.append("High cholesterol")
    if hdl and hdl < (50 if sex == "female" else 40):
        hf.append("Low HDL (good) cholesterol")
    if bmi and bmi >= 27.5:
        hf.append(f"Obesity (BMI {bmi})")
    if any(("heart" in f or "cardiac" in f) for f in family):
        hf.append("Heart disease in the family")
    if activity == "inactive":
        hf.append("Little physical activity")
    if not (tc or ldl):
        missing.append("cholesterol test (lipid profile)")
    level = "high" if len(hf) >= 4 or _has(conditions, "heart", "angina", "stroke") else "moderate" if len(hf) >= 2 else "low"
    risks.append({
        "key": "heart", "title": "Heart disease & stroke", "level": level, "score": len(hf), "score_label": "risk factors",
        "factors": hf or ["No major risk factors found yet"],
        "tips": (["Stop smoking — the single biggest step for your heart"] if smoker else [])
                + ["Lipid profile every 1–5 years (yearly if you have diabetes)", "Keep BP below 130/80",
                   "Use less ghee/oil, more vegetables, fruit and lentils"]
                + (["Chest pain on walking or at rest needs a doctor today"] if level == "high" else []),
    })

    # ---- Weight ----
    if bmi:
        if bmi >= 27.5:
            cat, level = "Obese (Asian cut-off)", "high"
        elif bmi >= 23:
            cat, level = "Overweight (Asian cut-off)", "moderate"
        elif bmi < 18.5:
            cat, level = "Underweight", "moderate"
        else:
            cat, level = "Healthy", "low"
        risks.append({"key": "weight", "title": "Weight (BMI)", "level": level, "score": bmi, "score_label": "BMI",
                      "factors": [f"BMI {bmi}: {cat}"],
                      "tips": ["Aim for BMI 18.5–22.9", "Small portions, no sugary drinks, walk daily"]
                              if level != "low" else ["Keep your weight steady with regular activity"]})
    else:
        missing.append("height and weight")

    # ---- Kidney ----
    kf = []
    cr, egfr = labs.get("Serum creatinine"), labs.get("eGFR")
    if has_diabetes:
        kf.append("Diabetes")
    if has_htn or (sys_bp and sys_bp >= 140):
        kf.append("High blood pressure")
    if cr and cr > (1.1 if sex == "female" else 1.3):
        kf.append(f"Creatinine {cr} mg/dL (above normal)")
    if egfr and egfr < 60:
        kf.append(f"eGFR {egfr} (below 60)")
    level = "high" if (egfr and egfr < 60) or (cr and cr > 1.5) else "moderate" if kf else "low"
    risks.append({"key": "kidney", "title": "Kidney disease", "level": level, "score": len(kf), "score_label": "risk factors",
                  "factors": kf or ["No kidney risk factors found"],
                  "tips": ["Drink enough water", "Avoid frequent painkillers like ibuprofen/diclofenac",
                           "Yearly creatinine and urine test if you have diabetes or high BP"]})

    # ---- Anaemia ----
    hb = labs.get("Haemoglobin (Hb)")
    if hb:
        low = 12.0 if sex == "female" else 13.5
        level = "high" if hb < low - 2 else "moderate" if hb < low else "low"
        risks.append({"key": "anaemia", "title": "Anaemia (low blood)", "level": level, "score": hb, "score_label": "Hb g/dL",
                      "factors": [f"Latest haemoglobin {hb} g/dL (normal from {low})"],
                      "tips": ["Iron-rich food: meat, liver, lentils, spinach, with lemon/vitamin C",
                               "No tea right after meals"] + (["See a doctor about the cause"] if level != "low" else [])})

    order = {"high": 0, "moderate": 1, "low": 2}
    risks.sort(key=lambda r: order[r["level"]])
    overall = risks[0]["level"] if risks else "low"
    recs = []
    for r in risks:
        if r["level"] != "low":
            recs.extend(r["tips"][:2])
    recs = list(dict.fromkeys(recs))[:6] or ["Keep up your healthy habits and do a yearly check-up"]
    return {"overall": overall, "bmi": bmi, "risks": risks, "recommendations": recs,
            "missing": list(dict.fromkeys(missing)),
            "note": "Estimates from your saved data to discuss with your doctor — not a diagnosis."}
