import json

from app.ai.providers import AIProviderError
from app.ai.service import AIService
from tests.conftest import VALID_USER, auth_header
from tests.test_ai import FakeProvider

AI_REPLY = {
    "possible_causes": [
        {"name": "Viral fever", "likelihood": "high", "reason": "Fever and body aches for 2 days."},
        {"name": "Dengue fever", "likelihood": "medium", "reason": "Fever with body pain is common in dengue season."},
    ],
    "triage_level": "routine",
    "triage_reason": "No danger signs described.",
    "next_steps": ["Rest and drink plenty of fluids.", "Take 500 mg paracetamol every 6 hours."],
    "follow_up_questions": ["Do you have a rash?"],
    "tests_to_discuss": ["Complete blood count (CBC)"],
    "specialist_type": "General physician",
    "warning_signs": ["Bleeding gums", "Severe stomach pain"],
}

REQUEST = {"symptoms": "fever and body aches", "duration": "2 days", "severity": 5, "age": 24}


def _use_ai(client, *replies):
    fake = FakeProvider("gemini", list(replies))
    client.app.state.ai = AIService([fake], retry_delay=0)
    return fake


def test_symptom_check_returns_validated_result(registered):
    client, tokens = registered
    _use_ai(client, json.dumps(AI_REPLY))
    response = client.post("/assessments/symptoms", headers=auth_header(tokens), json=REQUEST)
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["emergency"] is False
    assert body["triage_level"] == "routine"
    assert body["possible_causes"][0]["name"] == "Viral fever"
    assert "not a medical diagnosis" in body["disclaimer"]
    assert body["explanation"]["ai_provider"] == "gemini"
    assert body["explanation"]["prompt_version"] == "symptom-v2"


def test_dosing_advice_is_removed(registered):
    client, tokens = registered
    _use_ai(client, json.dumps(AI_REPLY))
    body = client.post("/assessments/symptoms", headers=auth_header(tokens), json=REQUEST).json()
    assert all("mg" not in step for step in body["next_steps"])
    assert any("dose" in rule for rule in body["explanation"]["rules_triggered"])


def test_red_flag_answers_immediately_without_ai(registered):
    client, tokens = registered
    fake = _use_ai(client)  # no replies: any AI call would fail the test
    response = client.post("/assessments/symptoms", headers=auth_header(tokens),
                           json={**REQUEST, "symptoms": "severe chest pain and sweating"})
    body = response.json()
    assert response.status_code == 201
    assert fake.calls == 0
    assert body["emergency"] is True and body["triage_level"] == "critical"
    assert any(n["number"] == "1122" for n in body["emergency_numbers"])
    assert body["explanation"]["ai_provider"] is None


def test_high_severity_raises_routine_triage(registered):
    client, tokens = registered
    _use_ai(client, json.dumps(AI_REPLY))
    body = client.post("/assessments/symptoms", headers=auth_header(tokens),
                       json={**REQUEST, "severity": 9}).json()
    assert body["triage_level"] == "moderate"


def test_ai_down_gives_friendly_503(registered):
    client, tokens = registered
    _use_ai(client, AIProviderError("gemini", "x"), AIProviderError("gemini", "x"))
    response = client.post("/assessments/symptoms", headers=auth_header(tokens), json=REQUEST)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "ai_unavailable"


def test_input_validation(registered):
    client, tokens = registered
    response = client.post("/assessments/symptoms", headers=auth_header(tokens), json={**REQUEST, "severity": 11})
    assert response.status_code == 422


def test_requires_login(client):
    assert client.post("/assessments/symptoms", json=REQUEST).status_code == 401


def test_history_is_private(registered):
    client, tokens_a = registered
    _use_ai(client, json.dumps(AI_REPLY))
    created = client.post("/assessments/symptoms", headers=auth_header(tokens_a), json=REQUEST).json()

    history = client.get("/assessments/symptoms", headers=auth_header(tokens_a)).json()
    assert [h["id"] for h in history] == [created["id"]]
    assert client.get(f"/assessments/symptoms/{created['id']}", headers=auth_header(tokens_a)).status_code == 200

    tokens_b = client.post("/auth/register", json={**VALID_USER, "email": "b@example.com"}).json()
    assert client.get("/assessments/symptoms", headers=auth_header(tokens_b)).json() == []
    other = client.get(f"/assessments/symptoms/{created['id']}", headers=auth_header(tokens_b))
    assert other.status_code == 404
    assert client.get("/assessments/symptoms/not-an-id", headers=auth_header(tokens_a)).status_code == 404


def test_chat_style_request_needs_only_symptoms(registered):
    client, tokens = registered
    _use_ai(client, json.dumps({**AI_REPLY, "ready": False}))
    r = client.post("/assessments/symptoms", headers=auth_header(tokens), json={"symptoms": "fever and body aches"})
    assert r.status_code == 201, r.text
    assert r.json()["explanation"]["inputs_used"] == ["symptoms"]
    assert r.json()["ready"] is False and r.json()["follow_up_questions"] == ["Do you have a rash?"]


def test_finished_result_has_no_questions_and_safe_otc(registered):
    client, tokens = registered
    _use_ai(client, json.dumps({**AI_REPLY, "ready": True, "otc_options": [
        {"name": "Paracetamol", "helps_with": "fever, aches", "avoid_if": "liver disease"},
        {"name": "Ibuprofen", "helps_with": "pain", "avoid_if": "ulcer"},
        {"name": "Amoxicillin", "helps_with": "infection", "avoid_if": ""},
        {"name": "Cetirizine", "helps_with": "500 mg twice daily", "avoid_if": ""}]}))
    r = client.post("/assessments/symptoms", headers=auth_header(tokens),
                    json={"symptoms": "fever, maybe dengue, body aches"}).json()
    assert r["ready"] and r["follow_up_questions"] == []
    names = [o["name"] for o in r["otc_options"]]
    assert names == ["paracetamol", "cetirizine"]  # no antibiotic; no ibuprofen when dengue is mentioned
    assert r["otc_options"][1]["helps_with"] == ""   # dose text removed


def test_no_otc_when_urgent_or_child(registered):
    client, tokens = registered
    otc = [{"name": "paracetamol", "helps_with": "fever", "avoid_if": ""}]
    _use_ai(client, json.dumps({**AI_REPLY, "triage_level": "urgent", "otc_options": otc}),
            json.dumps({**AI_REPLY, "otc_options": otc}))
    h = auth_header(tokens)
    assert client.post("/assessments/symptoms", headers=h, json={"symptoms": "high fever"}).json()["otc_options"] == []
    assert client.post("/assessments/symptoms", headers=h,
                       json={"symptoms": "fever", "age": 6}).json()["otc_options"] == []


def test_chat_answers_are_saved_with_the_result(registered):
    client, tokens = registered
    _use_ai(client, json.dumps(AI_REPLY))
    qa = [{"question": "How long?", "answer": "2 days"}]
    created = client.post("/assessments/symptoms", headers=auth_header(tokens),
                          json={"symptoms": "back pain", "answers": qa}).json()
    again = client.get(f"/assessments/symptoms/{created['id']}", headers=auth_header(tokens)).json()
    assert again["answers"] == qa
