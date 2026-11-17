import io

from pypdf import PdfReader

from tests.conftest import auth_header


def _setup(client, h):
    client.patch("/profile", headers=h, json={"date_of_birth": "1970-05-01", "gender": "male",
                                               "conditions": ["Hypertension"], "allergies": ["Penicillin"]})
    client.put("/health-risk/lifestyle", headers=h, json={"height_cm": 170, "weight_kg": 85, "waist_cm": 102,
                                                          "smoker": True, "activity": "inactive",
                                                          "diabetes_parents": "one", "family_history": ["heart disease"]})
    for s, d in ((150, 95), (142, 90)):
        assert client.post("/vitals", headers=h, json={"kind": "bp", "value": s, "value2": d}).status_code == 201
    client.post("/vitals", headers=h, json={"kind": "sugar_fasting", "value": 105})


def test_vitals_validation_and_trends(registered):
    client, tokens = registered
    h = auth_header(tokens)
    assert client.post("/vitals", headers=h, json={"kind": "heart_rate", "value": 1200}).status_code == 422
    assert client.post("/vitals", headers=h, json={"kind": "bp", "value": 120}).status_code == 422
    _setup(client, h)
    t = client.get("/health-trends", headers=h).json()
    bp = next(v for v in t["vitals"] if v["kind"] == "bp")
    assert bp["stats"]["count"] == 2 and bp["stats"]["direction"] == "down" and not bp["stats"]["in_normal_range"]
    r = client.post("/vitals/batch", headers=h, json={"readings": [{"kind": "heart_rate", "value": 72, "source": "watch"},
                                                                  {"kind": "heart_rate", "value": 900, "source": "watch"}]})
    assert r.json()["saved"] == 1


def test_risk_is_explained(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _setup(client, h)
    risk = client.get("/health-risk", headers=h).json()
    by = {r["key"]: r for r in risk["risks"]}
    assert by["diabetes"]["level"] == "high" and by["diabetes"]["score"] == 30 + 20 + 30 + 10
    assert by["heart"]["level"] == "high" and "Smoking" in by["heart"]["factors"]
    assert by["bp"]["level"] == "high" and by["weight"]["score"] == 29.4
    assert risk["overall"] == "high" and risk["recommendations"]
    assert "cholesterol test (lipid profile)" in risk["missing"]


def test_record_pdf_locked_with_login_password(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _setup(client, h)
    rec = client.get("/health-record", headers=h).json()
    assert rec["patient"]["allergies"] == ["Penicillin"] and rec["vitals"]["bp"]["value"] == 142
    assert client.post("/health-record/pdf", headers=h, json={"password": "wrong"}).status_code == 403
    pdf = client.post("/health-record/pdf", headers=h, json={"password": "Secure123"})
    assert pdf.status_code == 200 and pdf.headers["content-type"] == "application/pdf"
    reader = PdfReader(io.BytesIO(pdf.content))
    assert reader.is_encrypted and reader.decrypt("Secure123")
    assert "Penicillin" in reader.pages[0].extract_text()


def test_qr_share_link(registered):
    client, tokens = registered
    h = auth_header(tokens)
    share = client.post("/health-record/share", headers=h, json={"password": "Secure123"}).json()
    path = share["url"].split("://", 1)[1].split("/", 1)[1]
    got = client.get("/" + path)
    assert got.status_code == 200 and PdfReader(io.BytesIO(got.content)).is_encrypted
    assert client.delete("/health-record/share", headers=h).status_code == 204
    assert client.get("/" + path).status_code == 404


def test_record_has_ai_medicines_and_doctor_websites(registered):
    import asyncio
    from datetime import datetime, timezone
    client, tokens = registered
    h = auth_header(tokens)
    client.patch("/profile", headers=h, json={"city": "Faisalabad"})
    db = client.app.state.db
    user = asyncio.run(db.users.find_one({}))
    asyncio.run(db.symptom_assessments.insert_one({
        "user_id": user["_id"], "created_at": datetime.now(timezone.utc), "symptoms": "fever and body ache",
        "triage_level": "routine", "specialist_type": "General Physician", "possible_causes": [{"name": "Viral fever"}],
        "otc_options": [{"name": "Paracetamol", "helps_with": "fever", "avoid_if": "liver disease"}]}))
    rec = client.get("/health-record", headers=h).json()
    assert rec["ai_medicines"][0]["name"] == "Paracetamol"
    doc = rec["recommended_doctors"][0]
    assert doc["specialist"] == "General Physician"
    assert {w["url"] for w in doc["websites"]} == {"https://www.marham.pk/doctors/faisalabad/general-physician",
                                                   "https://oladoc.com/pakistan/faisalabad/general-physician"}
    pdf = client.post("/health-record/pdf", headers=h, json={"password": "Secure123"})
    reader = PdfReader(io.BytesIO(pdf.content))
    reader.decrypt("Secure123")
    text = "".join(p.extract_text() for p in reader.pages)
    assert "Paracetamol" in text and "Marham" in text and "oladoc" in text
