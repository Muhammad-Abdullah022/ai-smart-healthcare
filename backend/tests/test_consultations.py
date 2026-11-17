import json

from app.ai.service import AIService
from tests.conftest import auth_header
from tests.test_ai import FakeProvider

DOCTOR = {"full_name": "Sara Malik", "email": "drsara@example.com", "password": "Secure123", "accepted_terms": True}
JOIN = {"name": "Sara Malik", "pmdc_number": "12345-P", "specialty": "General Physician", "city": "Lahore",
        "clinic": "Malik Clinic", "address": "12 Main Blvd, Gulberg", "phone": "0300-0000000", "timings": "5-9 pm",
        "fee_pkr": 1500, "payment_method": "JazzCash", "payment_title": "Sara Malik", "payment_account": "03001234567"}
PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 100


def _admin(client):
    import asyncio
    tokens = client.post("/auth/register", json={**DOCTOR, "email": "admin@example.com", "full_name": "Admin"}).json()
    asyncio.run(client.app.state.db.users.update_one({"email": "admin@example.com"}, {"$set": {"roles": ["admin"]}}))
    return auth_header(tokens)


def _doctor(client):
    """Doctor signs up -> cannot log in -> admin approves -> doctor logs in."""
    r = client.post("/auth/register-doctor", json={**DOCTOR, "doctor": JOIN})
    assert r.status_code == 202, r.text
    login = client.post("/auth/login", json={"email": DOCTOR["email"], "password": DOCTOR["password"]})
    assert login.status_code == 403 and login.json()["error"]["code"] == "pending_approval"
    admin = _admin(client)
    pending = client.get("/admin/doctors", headers=admin).json()
    assert pending[0]["approval"] == "pending"
    doctor_id = pending[0]["id"]
    assert client.post(f"/admin/doctors/{doctor_id}/approve", headers=admin).json()["approval"] == "approved"
    tokens = client.post("/auth/login", json={"email": DOCTOR["email"], "password": DOCTOR["password"]}).json()
    return tokens, auth_header(tokens), doctor_id


def test_full_consultation_flow_with_live_events(registered):
    client, tokens = registered
    patient = auth_header(tokens)
    doc_tokens, doctor, doctor_id = _doctor(client)
    listed = client.get("/doctors", headers=patient, params={"city": "Lahore"}).json()["doctors"]
    assert listed[0]["id"] == doctor_id and listed[0]["online"]

    with client.websocket_connect(f"/ws?token={doc_tokens['access_token']}") as ws:
        assert ws.receive_json()["type"] == "hello"
        c = client.post("/consultations", headers=patient, json={"doctor_id": doctor_id, "reason": "Fever for 3 days"})
        assert c.status_code == 201
        cid = c.json()["id"]
        event = ws.receive_json()
        assert event["type"] == "message" and event["message"]["text"] == "Fever for 3 days"

    panel = client.get("/doctor-panel/consultations", headers=doctor).json()
    assert panel["stats"]["new"] == 1
    # No payment details and no prescription before the doctor accepts and is paid.
    assert "payment" not in client.get(f"/consultations/{cid}", headers=patient).json()
    rx = {"medicines": [{"name": "Panadol", "strength": "500 mg", "how_to_take": "1 tablet three times a day",
                         "duration_days": 3}]}
    assert client.post(f"/consultations/{cid}/prescribe", headers=doctor, json=rx).status_code == 409
    assert client.post(f"/consultations/{cid}/accept", headers=patient).status_code == 403

    assert client.post(f"/consultations/{cid}/accept", headers=doctor).json()["status"] == "awaiting_payment"
    detail = client.get(f"/consultations/{cid}", headers=patient).json()
    assert detail["payment"]["account"] == "03001234567" and detail["payment"]["amount_pkr"] == 1500

    client.app.state.ai = AIService([FakeProvider("gemini", [json.dumps(
        {"looks_like_payment": True, "app": "JazzCash", "amount_pkr": 1500, "transaction_id": "TID998877",
         "paid_to": "Sara Malik", "date": "17 Nov 2026"})])], retry_delay=0)
    pay = client.post(f"/consultations/{cid}/payment", headers=patient, files={"file": ("pay.png", PNG, "image/png")})
    assert pay.status_code == 200 and pay.json()["meta"]["amount_matches"]
    assert pay.json()["meta"]["transaction_id"] == "TID998877"
    file_id = pay.json()["meta"]["file_id"]
    assert client.get(f"/consultations/{cid}/files/{file_id}", headers=doctor).content == PNG

    assert client.post(f"/consultations/{cid}/payment/verify", headers=doctor, json={"ok": True}).json()["status"] == "paid"
    r = client.post(f"/consultations/{cid}/prescribe", headers=doctor, json=rx)
    assert r.status_code == 200
    got = client.get(f"/prescriptions/{r.json()['prescription_id']}", headers=patient).json()
    assert got["status"] == "needs_review" and got["reading"]["medicines"][0]["name"] == "Panadol"

    msgs = client.get(f"/consultations/{cid}", headers=patient).json()["messages"]
    assert [m["kind"] for m in msgs][-1] == "prescription"
    assert client.post(f"/consultations/{cid}/messages", headers=patient, json={"text": "Thank you"}).status_code == 201


def test_visit_clinic_and_privacy(registered):
    client, tokens = registered
    patient = auth_header(tokens)
    _, doctor, doctor_id = _doctor(client)
    cid = client.post("/consultations", headers=patient, json={"doctor_id": doctor_id, "reason": "Chest pain",
                                                               "share_assessment": True}).json()["id"]
    r = client.post(f"/consultations/{cid}/visit-clinic", headers=doctor,
                    json={"urgency": "emergency", "reason": "Chest pain needs an ECG now"})
    assert r.json()["status"] == "visit_clinic"
    last = client.get(f"/consultations/{cid}", headers=patient).json()["messages"][-1]
    assert last["kind"] == "clinic_visit" and "1122" in last["text"] and last["meta"]["address"]

    other = client.post("/auth/register", json={**DOCTOR, "email": "x@example.com"}).json()
    # A normal user cannot make themselves a doctor.
    assert client.put("/doctor-panel/me", headers=auth_header(other), json=JOIN).status_code == 403
    assert client.get(f"/consultations/{cid}", headers=auth_header(other)).status_code == 404
    assert client.get("/doctor-panel/consultations", headers=auth_header(other)).status_code == 403


def test_cannot_consult_offline_doctor(registered):
    client, tokens = registered
    h = auth_header(tokens)
    import asyncio
    oid = asyncio.run(client.app.state.db.doctors.insert_one({"name": "Dr. X", "specialty": "General Physician"})).inserted_id
    r = client.post("/consultations", headers=h, json={"doctor_id": str(oid), "reason": "Fever"})
    assert r.status_code == 409 and r.json()["error"]["code"] == "not_online"


def test_admin_manages_accounts_and_issues(registered):
    client, tokens = registered
    patient = auth_header(tokens)
    # Pending doctors are not offered to patients.
    client.post("/auth/register-doctor", json={**DOCTOR, "email": "wait@example.com",
                                                "doctor": {**JOIN, "pmdc_number": "999-P"}})
    assert not any(d["online"] for d in client.get("/doctors", headers=patient, params={"city": "Lahore"}).json()["doctors"])
    assert client.post("/auth/register-doctor", json={**DOCTOR, "email": "dup@example.com",
                                                      "doctor": {**JOIN, "pmdc_number": "999-P"}}).status_code == 409
    tokens_d, doctor, doctor_id = _doctor(client)
    admin = auth_header(client.post("/auth/login", json={"email": "admin@example.com", "password": "Secure123"}).json())
    assert client.get("/admin/doctors", headers=patient).status_code == 403
    stats = client.get("/admin/stats", headers=admin).json()
    assert stats["doctors"] == 2 and stats["pending_doctors"] == 1

    waiting = next(d for d in client.get("/admin/doctors", headers=admin).json() if d["approval"] == "pending")
    r = client.post(f"/admin/doctors/{waiting['id']}/reject", headers=admin, json={"reason": "PMDC number not found."})
    assert r.json()["approval"] == "rejected"
    login = client.post("/auth/login", json={"email": "wait@example.com", "password": DOCTOR["password"]})
    assert login.status_code == 403 and "PMDC number not found" in login.json()["error"]["message"]

    assert client.put("/doctor-panel/me", headers=doctor, json={**JOIN, "fee_pkr": 2000}).json()["fee_pkr"] == 2000
    r = client.post(f"/admin/doctors/{doctor_id}/status", headers=admin, json={"active": False})
    assert r.json()["active"] is False
    assert client.post("/auth/login", json={"email": DOCTOR["email"], "password": DOCTOR["password"]}).status_code == 403
    assert client.get("/auth/me", headers=doctor).status_code == 401
    client.post(f"/admin/doctors/{doctor_id}/status", headers=admin, json={"active": True})
    assert client.post(f"/admin/doctors/{doctor_id}/reset-password", headers=admin,
                       json={"password": "Reset1234"}).status_code == 204
    d2 = auth_header(client.post("/auth/login", json={"email": DOCTOR["email"], "password": "Reset1234"}).json())
    assert client.post("/auth/change-password", headers=d2,
                       json={"current_password": "Reset1234", "new_password": "NewPass123"}).status_code == 204

    # Issues: patient reports a payment problem about a consultation; admin replies and resolves.
    cid = client.post("/consultations", headers=patient, json={"doctor_id": doctor_id, "reason": "Fever"}).json()["id"]
    issue = client.post("/issues", headers=patient, json={"category": "payment", "subject": "Paid but not confirmed",
                                                          "message": "I paid Rs 1500", "consultation_id": cid})
    assert issue.status_code == 201
    iid = issue.json()["id"]
    listed = client.get("/admin/issues", headers=admin).json()
    assert listed[0]["consultation"]["fee_pkr"] == 2000 and "messages" in listed[0]
    assert client.get("/admin/issues", headers=patient).status_code == 403
    r = client.post(f"/issues/{iid}/messages", headers=admin, json={"text": "We asked the doctor to check."})
    assert r.json()["status"] == "in_progress"
    assert client.post(f"/admin/issues/{iid}/status", headers=admin, json={"status": "resolved"}).json()["status"] == "resolved"
    mine = client.get("/issues", headers=patient).json()
    assert mine[0]["messages"][-1]["from"] == "admin" and "user_email" not in mine[0]
    users = client.get("/admin/users", headers=admin).json()
    assert {"ayesha@example.com", DOCTOR["email"]} <= {u["email"] for u in users}
