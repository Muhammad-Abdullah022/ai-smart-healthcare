"""Builds data/doctors/demo_doctors.csv: made-up doctor profiles for every supported city (FYP demo).

Every row has demo=yes and the app labels these profiles "Demo profile". Names are invented
combinations; any match with a real person is a coincidence. Run:  python scripts/make_demo_doctors.py
"""
import csv
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CITIES = ROOT / "data" / "labs" / "all_target_cities_tehsils.csv"
OUT = ROOT / "data" / "doctors" / "demo_doctors.csv"
SEED = 20261117

BIG = {"Lahore", "Faisalabad", "Rawalpindi", "Multan", "Gujranwala"}
ALL_SPECS = ["General Physician", "Cardiologist", "Dermatologist", "ENT Specialist", "Gastroenterologist",
             "Gynecologist", "Neurologist", "Orthopedic Surgeon", "Pediatrician", "Psychiatrist", "Pulmonologist",
             "Urologist", "Nephrologist", "Endocrinologist", "Eye Specialist", "General Surgeon", "Dentist",
             "Rheumatologist"]
DISTRICT_SPECS = ["General Physician", "Gynecologist", "Pediatrician", "Cardiologist", "Dermatologist",
                  "ENT Specialist", "Orthopedic Surgeon", "Eye Specialist", "General Surgeon", "Gastroenterologist",
                  "Psychiatrist", "Dentist"]
TEHSIL_SPECS = ["General Physician", "General Physician", "Gynecologist", "Pediatrician", "Dentist",
                "Orthopedic Surgeon"]

MALE = ["Ahmed", "Usman", "Bilal", "Hamza", "Kamran", "Imran", "Faisal", "Adnan", "Zeeshan", "Waqas", "Shahid",
        "Nadeem", "Asif", "Tariq", "Rizwan", "Junaid", "Saad", "Haris", "Omer", "Fahad", "Salman", "Naveed",
        "Arslan", "Yasir", "Sohail", "Khurram", "Atif", "Mudassar", "Shoaib", "Zubair"]
FEMALE = ["Ayesha", "Fatima", "Sana", "Hina", "Maryam", "Saima", "Nida", "Rabia", "Amna", "Sadia", "Mehwish",
          "Iqra", "Zainab", "Farah", "Uzma", "Bushra", "Sidra", "Anum", "Asma", "Kiran"]
LAST = ["Malik", "Chaudhry", "Butt", "Sheikh", "Qureshi", "Javed", "Iqbal", "Rana", "Akhtar", "Hussain", "Raza",
        "Mirza", "Siddiqui", "Bhatti", "Anwar", "Riaz", "Saleem", "Aslam", "Nawaz", "Hashmi", "Gillani", "Abbasi",
        "Khalid", "Rasheed", "Arshad", "Zafar", "Mehmood", "Sabir", "Latif", "Kazmi"]
QUAL = {
    "General Physician": ["MBBS, FCPS (Medicine)", "MBBS, MCPS (Family Medicine)", "MBBS, FCPS (Medicine)"],
    "Cardiologist": ["MBBS, FCPS (Cardiology)", "MBBS, MRCP (UK), FCPS (Cardiology)"],
    "Dermatologist": ["MBBS, FCPS (Dermatology)", "MBBS, MCPS (Dermatology)"],
    "ENT Specialist": ["MBBS, FCPS (ENT)", "MBBS, DLO, FCPS (ENT)"],
    "Gastroenterologist": ["MBBS, FCPS (Gastroenterology)"],
    "Gynecologist": ["MBBS, FCPS (Obs & Gynae)", "MBBS, MCPS (Gynae), DGO"],
    "Neurologist": ["MBBS, FCPS (Neurology)"],
    "Orthopedic Surgeon": ["MBBS, FCPS (Orthopaedics)", "MBBS, MS (Orthopaedics)"],
    "Pediatrician": ["MBBS, FCPS (Paediatrics)", "MBBS, DCH, MCPS (Paeds)"],
    "Psychiatrist": ["MBBS, FCPS (Psychiatry)"],
    "Pulmonologist": ["MBBS, FCPS (Pulmonology)"],
    "Urologist": ["MBBS, FCPS (Urology)"],
    "Nephrologist": ["MBBS, FCPS (Nephrology)"],
    "Endocrinologist": ["MBBS, FCPS (Endocrinology)"],
    "Eye Specialist": ["MBBS, FCPS (Ophthalmology)", "MBBS, DOMS"],
    "General Surgeon": ["MBBS, FCPS (Surgery)", "MBBS, MS (General Surgery)"],
    "Dentist": ["BDS, FCPS (Operative Dentistry)", "BDS, MCPS"],
    "Rheumatologist": ["MBBS, FCPS (Rheumatology)"],
}
FOCUS = {
    "General Physician": "fever, infections, diabetes, blood pressure and general check-ups",
    "Cardiologist": "chest pain, blood pressure, heart rhythm problems and heart failure",
    "Dermatologist": "acne, eczema, fungal infections, allergies and hair fall",
    "ENT Specialist": "ear infections, sinus problems, tonsils and hearing problems",
    "Gastroenterologist": "acidity, ulcers, hepatitis, IBS and liver disease",
    "Gynecologist": "pregnancy care, PCOS, period problems and women's health",
    "Neurologist": "migraine, fits, stroke, nerve pain and numbness",
    "Orthopedic Surgeon": "joint pain, back pain, fractures and sports injuries",
    "Pediatrician": "child fever, growth, vaccination and newborn care",
    "Psychiatrist": "depression, anxiety, sleep problems and stress",
    "Pulmonologist": "asthma, COPD, TB, chronic cough and breathing problems",
    "Urologist": "kidney stones, urine problems and prostate issues",
    "Nephrologist": "kidney disease, dialysis and high blood pressure from kidneys",
    "Endocrinologist": "diabetes, thyroid problems and hormone disorders",
    "Eye Specialist": "eye infections, weak eyesight, cataract and glaucoma",
    "General Surgeon": "appendix, gallstones, hernia and small surgical procedures",
    "Dentist": "tooth pain, fillings, root canal and gum problems",
    "Rheumatologist": "arthritis, gout and joint swelling",
}
BASE_FEE = {"General Physician": 1000, "Dentist": 1000, "Pediatrician": 1500, "Gynecologist": 1800}
CLINIC = ["{l} Clinic", "City Care Clinic", "{l} Medical Centre", "Shifa Clinic", "Al-Rehman Clinic",
          "Medicare Hospital", "Family Health Clinic", "{c} Medical Complex", "Noor Hospital", "Life Care Hospital"]
ROADS = ["Main Bazar", "G.T. Road", "Railway Road", "College Road", "Jail Road", "Hospital Road", "Club Road",
         "Canal Road", "Stadium Road", "Kutchery Road"]
TIMES = ["Mon–Sat, 5 pm – 9 pm", "Mon–Fri, 6 pm – 10 pm", "Mon–Sat, 10 am – 2 pm", "Daily, 4 pm – 8 pm",
         "Mon–Thu, 7 pm – 10 pm"]


def main() -> None:
    r = random.Random(SEED)
    rows = list(csv.DictReader(CITIES.open(encoding="utf-8-sig")))
    out = []
    for c in rows:
        city, district = c["city_or_tehsil_as_provided"].strip(), c["district_as_provided"].strip()
        if city in BIG:
            plan = [s for s in ALL_SPECS for _ in range(3)]
        elif city == district:
            plan = DISTRICT_SPECS + ["General Physician", "Gynecologist", "Pediatrician"]
        else:
            plan = TEHSIL_SPECS
        for spec in plan:
            female = r.random() < (0.85 if spec == "Gynecologist" else 0.35)
            first = r.choice(FEMALE if female else MALE)
            last = r.choice(LAST)
            years = r.randint(3, 28)
            base = BASE_FEE.get(spec, 2000) * (1.6 if city in BIG else 1.0 if city == district else 0.7)
            fee = int(round(base * (0.8 + years / 40) / 100) * 100)
            clinic = r.choice(CLINIC).format(l=last, c=city)
            road = r.choice(ROADS)
            out.append({
                "city": city, "doctor_name": f"Dr. {first} {last}", "specialty": spec,
                "qualification": r.choice(QUAL[spec]), "clinic_name": clinic,
                "address": f"{clinic}, {road}, {city}", "fee_pkr": fee,
                "phone": f"03{r.choice(['00', '01', '03', '21', '33', '45'])}-{r.randint(1000000, 9999999)}",
                "email": "", "timings": r.choice(TIMES), "source_url": "", "checked_date": "",
                "experience_years": years, "gender": "female" if female else "male",
                "about": (f"{years} years of experience as a {spec.lower()}. Sees patients for {FOCUS[spec]}. "
                          f"Demo profile for the FYP — not a real doctor."),
                "demo": "yes",
            })
    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0]))
        w.writeheader()
        w.writerows(out)
    print(f"wrote {len(out)} demo doctors for {len(rows)} cities -> {OUT}")


if __name__ == "__main__":
    main()
