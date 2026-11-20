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
    # Only real doctors: no made-up demo profiles, every doctor has a source.
    assert data and not any(d["demo"] for d in data) and all(d["source_url"].startswith("https://") for d in data)


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



def test_default_doctor_logins_job(registered, tmp_path):
    import asyncio
    import json

    from openpyxl import load_workbook

    from app.doctor_logins import run_doctor_login_job
    client, tokens = registered
    db = client.app.state.db
    total = asyncio.run(db.doctors.count_documents({}))
    job = tmp_path / "doctor_logins.json"
    job.write_text(json.dumps({"password": "ABC12345"}))
    xlsx = tmp_path / "Doctor_Logins.xlsx"
    asyncio.run(run_doctor_login_job(db, job, xlsx))
    assert not job.exists()  # the password is not left on disk
    ws = load_workbook(xlsx).active
    rows = [r for r in ws.iter_rows(min_row=5, values_only=True) if r[0]]
    assert len(rows) == total and len({r[5] for r in rows}) == total
    assert all(r[5].endswith("@example.com") and r[6] == "ABC12345" for r in rows)

    name, email = rows[0][1], rows[0][5]
    login = client.post("/auth/login", json={"email": email, "password": "ABC12345"})
    assert login.status_code == 200
    doctor = auth_header(login.json())
    assert client.get("/auth/me", headers=doctor).json()["must_change_password"]
    me = client.get("/doctor-panel/me", headers=doctor).json()
    assert me["name"] == name and me["available"] is False

    # Not "online" for patients until the doctor turns Available on, but a booking still reaches the panel.
    patient = auth_header(tokens)
    d = next(x for x in client.get("/doctors", headers=patient, params={"city": me["city"], "specialty": me["specialty"], "limit": 200}).json()["doctors"]
             if x["id"] == me["id"])
    assert d["has_account"] and not d["online"]
    cid = client.post("/consultations", headers=patient, json={"doctor_id": me["id"], "reason": "Pain"}).json()["id"]
    assert client.get("/doctor-panel/consultations", headers=doctor).json()["stats"]["new"] == 1
    assert client.post(f"/consultations/{cid}/accept", headers=doctor).json()["status"] == "paid"  # no fee listed

    # Running the job again makes no duplicates and shows changed passwords as changed.
    client.post("/auth/change-password", headers=doctor, json={"current_password": "ABC12345", "new_password": "Mine12345"})
    job.write_text(json.dumps({"password": "ABC12345"}))
    asyncio.run(run_doctor_login_job(db, job, xlsx))
    rows2 = [r for r in load_workbook(xlsx).active.iter_rows(min_row=5, values_only=True) if r[0]]
    assert len(rows2) == total and next(r for r in rows2 if r[5] == email)[6] == "(changed by the doctor)"
