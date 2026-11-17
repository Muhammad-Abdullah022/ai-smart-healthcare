import json

from app.ai.providers import AIProviderError
from app.ai.service import AIService
from tests.conftest import auth_header
from tests.test_ai import FakeProvider


def _reply(second_name="Augmentin"):
    return json.dumps({
        "readable": True, "doctor_name": "Dr. A. Khan", "clinic": "City Clinic", "date": "12/11/2026",
        "summary": "Two medicines for a throat infection.",
        "medicines": [
            {"name": "Panadol", "generic_name": "Paracetamol", "strength": "500 mg", "form": "tablet",
             "dose_as_written": "1+1+1 x 3/7", "how_to_take": "1 tablet three times a day", "times_per_day": 3,
             "timing": "after food", "duration": "3 days", "duration_days": 3, "purpose": "pain and fever",
             "confidence": "high", "unclear_parts": ""},
            {"name": second_name, "generic_name": "", "strength": "", "form": "tablet", "dose_as_written": "1+0+1",
             "how_to_take": "morning and night", "times_per_day": 2, "timing": "", "duration": "",
             "duration_days": None, "purpose": "", "confidence": "low", "unclear_parts": ""},
        ],
        "notes": ["Follow up after 5 days"], "warnings": [],
    })


def _ai(client, *replies):
    fake = FakeProvider("gemini", list(replies))
    client.app.state.ai = AIService([fake], retry_delay=0)
    return fake


def _upload(client, tokens, mime="image/jpeg", data=b"\xff\xd8rx"):
    return client.post("/prescriptions", headers=auth_header(tokens), data={"language": "roman_ur"},
                       files={"file": ("rx.jpg", data, mime)})


def test_read_prescription_and_flag_unclear(registered):
    client, tokens = registered
    fake = _ai(client, _reply())
    r = _upload(client, tokens)
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["status"] == "needs_review" and fake.last_images[0][0] == "image/jpeg"
    meds = body["reading"]["medicines"]
    assert meds[0]["name"] == "Panadol" and meds[0]["times_per_day"] == 3
    assert meds[1]["confidence"] == "low" and meds[1]["unclear_parts"]  # filled in by code
    assert any("pharmacist" in w for w in body["reading"]["warnings"])
    assert client.get("/prescriptions", headers=auth_header(tokens)).json()[0]["medicines"] == ["Panadol", "Augmentin"]


def test_reminder_needs_verified_prescription(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _ai(client, _reply())
    rx = _upload(client, tokens).json()
    med = {"name": "Panadol", "strength": "500 mg", "times": ["08:00", "14:00", "20:00"], "prescription_id": rx["id"]}
    assert client.post("/medicines", headers=h, json=med).status_code == 409
    meds = rx["reading"]["medicines"]
    assert client.put(f"/prescriptions/{rx['id']}/confirm", headers=h,
                      json={"medicines": meds, "checked": False}).status_code == 422
    ok = client.put(f"/prescriptions/{rx['id']}/confirm", headers=h, json={"medicines": meds, "checked": True})
    assert ok.status_code == 200 and ok.json()["status"] == "verified"
    assert client.post("/medicines", headers=h, json=med).status_code == 201


def test_ai_down_then_retry_and_delete(registered):
    client, tokens = registered
    _ai(client, AIProviderError("gemini", "down"), _reply())
    body = _upload(client, tokens).json()
    assert body["status"] == "error" and body["error"]
    again = client.post(f"/prescriptions/{body['id']}/read", headers=auth_header(tokens)).json()
    assert again["status"] == "needs_review"
    assert _upload(client, tokens, mime="text/plain").status_code == 415
    assert client.delete(f"/prescriptions/{body['id']}", headers=auth_header(tokens)).status_code == 204
    assert client.get(f"/prescriptions/{body['id']}", headers=auth_header(tokens)).status_code == 404
