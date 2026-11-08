import json

from app.ai.providers import AIProviderError
from app.ai.service import AIService
from tests.conftest import VALID_USER, auth_header
from tests.test_ai import FakeProvider


def _reply(hb="10.2", flag="low"):
    return json.dumps({
        "report_type": "Complete blood count", "report_date": "2026-11-01",
        "values": [{"name": "Hemoglobin", "value": hb, "unit": "g/dL", "reference_range": "12-16", "flag": flag},
                   {"name": "WBC", "value": "7,200", "unit": "/uL", "reference_range": "4000-11000", "flag": "normal"}],
        "summary": "Hemoglobin is a little low.", "doctor_type": "General physician", "urgency": "soon",
        "next_steps": ["Show this report to a doctor this week."],
    })


def _upload(client, tokens, name="cbc.jpg", mime="image/jpeg", data=b"\xff\xd8fake-jpeg", lang="en"):
    return client.post("/reports", headers=auth_header(tokens), data={"language": lang},
                       files={"file": (name, data, mime)})


def _ai(client, *replies):
    fake = FakeProvider("gemini", list(replies))
    client.app.state.ai = AIService([fake], retry_delay=0)
    return fake


def test_upload_is_read_by_ai_with_image(registered):
    client, tokens = registered
    fake = _ai(client, _reply())
    r = _upload(client, tokens, lang="roman_ur")
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["analysis"]["values"][0]["flag"] == "low"
    assert body["language"] == "roman_ur"
    assert fake.last_images[0][0] == "image/jpeg"
    listed = client.get("/reports", headers=auth_header(tokens)).json()
    assert listed[0]["abnormal_count"] == 1 and listed[0]["report_type"] == "Complete blood count"
    f = client.get(f"/reports/{body['id']}/file", headers=auth_header(tokens))
    assert f.content == b"\xff\xd8fake-jpeg" and f.headers["content-type"] == "image/jpeg"


def test_wrong_type_and_empty_rejected(registered):
    client, tokens = registered
    assert _upload(client, tokens, name="x.exe", mime="application/x-msdownload").status_code == 415
    assert _upload(client, tokens, data=b"").status_code == 422


def test_ai_down_keeps_report_and_can_retry(registered):
    client, tokens = registered
    _ai(client, AIProviderError("gemini", "down"), _reply())
    body = _upload(client, tokens).json()
    assert body["analysis"] is None and body["error"]
    again = client.post(f"/reports/{body['id']}/analyze", headers=auth_header(tokens)).json()
    assert again["analysis"]["report_type"] == "Complete blood count"


def test_reports_are_private(registered):
    client, tokens = registered
    _ai(client, _reply())
    rid = _upload(client, tokens).json()["id"]
    other = client.post("/auth/register", json={**VALID_USER, "email": "o@example.com"}).json()
    assert client.get(f"/reports/{rid}", headers=auth_header(other)).status_code == 404
    assert client.get(f"/reports/{rid}/file", headers=auth_header(other)).status_code == 404
    assert client.get("/reports", headers=auth_header(other)).json() == []


def test_compare_old_vs_new(registered):
    client, tokens = registered
    _ai(client, _reply("10.2", "low"), _reply("12.8", "normal"))
    old = _upload(client, tokens).json()["id"]
    new = _upload(client, tokens).json()["id"]
    body = client.get(f"/reports/compare?old={old}&new={new}", headers=auth_header(tokens)).json()
    hb = next(r for r in body["rows"] if r["name"] == "Hemoglobin")
    assert hb["change"] == "up" and hb["now_normal"] is True
    wbc = next(r for r in body["rows"] if r["name"] == "WBC")
    assert wbc["change"] == "same"
