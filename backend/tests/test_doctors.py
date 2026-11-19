from datetime import date, timedelta

import app.routers.doctors as doctors_router
from app.doctors import normalize_specialty
from tests.conftest import auth_header


def _add_doctors(client):
    db = client.app.state.db
    docs = [
        {"city": "Testpur", "city_key": "testpur", "name": "Dr. Test One", "specialty": "General Physician",
         "qualification": "MBBS", "clinic": "Test Clinic", "address": "Main Road, Lahore", "fee_pkr": 1500.0,
         "phone": "042-0000000", "email": "clinic@example.com", "timings": "5-9 pm", "source_url": "https://example.com",
         "checked": "2026-11-10"},
        {"city": "Testpur", "city_key": "testpur", "name": "Dr. Test Two", "specialty": "Cardiologist",
         "qualification": "FCPS", "clinic": "Heart Care", "address": "Gulberg, Lahore", "fee_pkr": 3000.0,
         "phone": "", "email": "", "timings": "", "source_url": "", "checked": ""},
    ]
    import anyio
    anyio.run(db.doctors.insert_many, docs)


def test_specialty_mapping():
    assert normalize_specialty("General physician") == "General Physician"
    assert normalize_specialty("Cardiologist (heart specialist)") == "Cardiologist"
    assert normalize_specialty("ENT specialist") == "ENT Specialist"


def test_list_and_filter(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _add_doctors(client)
    data = client.get("/doctors", headers=h, params={"city": "Testpur", "specialty": "General physician"}).json()
    assert data["specialty"] == "General Physician" and [d["name"] for d in data["doctors"]] == ["Dr. Test One"]
    assert data["doctors"][0]["can_email"] is True and "email" not in data["doctors"][0]
    specs = client.get("/doctors/specialties", headers=h, params={"city": "Testpur"}).json()
    assert specs[0]["doctors"] == 1


def test_booking_emails_doctor(registered, monkeypatch):
    client, tokens = registered
    h = auth_header(tokens)
    _add_doctors(client)
    sent = {}

    async def fake_send(settings, to, subject, body, reply_to=None):
        sent.update(to=to, subject=subject, body=body, reply_to=reply_to)

    monkeypatch.setattr(doctors_router, "send_mail", fake_send)
    doc = client.get("/doctors", headers=h, params={"city": "Testpur", "specialty": "GP"}).json()["doctors"][0]
    r = client.post("/appointments/request", headers=h, json={
        "doctor_id": doc["id"], "preferred_date": (date.today() + timedelta(days=1)).isoformat(),
        "time_of_day": "evening", "reason": "Fever for 3 days", "source": "chat"})
    assert r.status_code == 201 and r.json()["status"] == "emailed"
    assert sent["to"] == "clinic@example.com" and "Fever for 3 days" in sent["body"]
    assert sent["reply_to"] and "Ayesha Khan" in sent["body"]
    assert client.get("/appointments", headers=h).json()[0]["status"] == "emailed"


def test_booking_without_email_is_saved(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _add_doctors(client)
    doc = client.get("/doctors", headers=h, params={"city": "Testpur", "specialty": "Cardiologist"}).json()["doctors"][0]
    r = client.post("/appointments/request", headers=h, json={
        "doctor_id": doc["id"], "preferred_date": date.today().isoformat(), "reason": "Chest check-up"}).json()
    assert r["status"] == "saved" and "call" in r["message"]


def test_booking_past_date_rejected(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _add_doctors(client)
    doc = client.get("/doctors", headers=h, params={"city": "Testpur"}).json()["doctors"][0]
    r = client.post("/appointments/request", headers=h, json={
        "doctor_id": doc["id"], "preferred_date": "2020-01-01", "reason": "check"})
    assert r.status_code == 422


def test_government_consultants_loaded(registered):
    client, tokens = registered
    data = client.get("/doctors", headers=auth_header(tokens), params={"city": "Okara"}).json()["doctors"]
    assert {d["specialty"] for d in data} >= {"Gynecologist", "Pulmonologist"}
    real = [d for d in data if not d["demo"]]
    assert real and all(d["source_url"].startswith("https://pshealthpunjab.gov.pk") for d in real)
    demo = [d for d in data if d["demo"]]
    assert demo and all(d["experience_years"] and d["fee_pkr"] and "Demo profile" in d["about"] for d in demo)
    assert [d["demo"] for d in data] == sorted(d["demo"] for d in data)  # real doctors listed first


def test_specialty_matching_picks_the_named_specialist():
    from app.doctors import normalize_specialty, specialties_for
    assert normalize_specialty("Pulmonologist (chest specialist) / General physician") == "Pulmonologist"
    assert normalize_specialty("Gastroenterologist") == "Gastroenterologist"   # not "ENT"
    assert normalize_specialty("Dentist") == "Dentist"                         # not "ENT"
    assert normalize_specialty("ENT specialist / General physician") == "ENT Specialist"
    assert normalize_specialty("Eye specialist (ophthalmologist)") == "Eye Specialist"
    assert normalize_specialty("Gynaecologist") == "Gynecologist"
    assert specialties_for("Cardiologist / General physician") == ["Cardiologist", "General Physician"]


def test_recommended_doctors_only_of_that_specialty(registered):
    client, tokens = registered
    h = auth_header(tokens)
    for spec in ("Cardiologist", "Dermatologist", "Pulmonologist (chest specialist) / General physician"):
        r = client.get("/doctors/recommended", headers=h, params={"specialty": spec, "city": "Lahore", "limit": 5})
        assert r.status_code == 200
        body = r.json()
        assert body["doctors"], spec
        assert {d["specialty"] for d in body["doctors"]} == {body["specialty"]}
        assert body["specialty"] == spec.split(" ")[0] or body["backup"]
