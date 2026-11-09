import json

from app.ai.service import AIService
from tests.conftest import VALID_USER, auth_header
from tests.test_ai import FakeProvider


def _consent(client, tokens):
    client.post("/consents", headers=auth_header(tokens), json={"category": "mental_health", "granted": True})


def _out(reply="I hear you.", **kw):
    base = {"message_type": "emotional", "mental_state": "stress", "severity": "moderate", "crisis_risk": "none",
            "emotional_tone": "overwhelmed", "key_concern": "exams", "reply": reply, "coping_tip": "Take a short walk.",
            "speech": ""}
    return json.dumps({**base, **kw})


def _ai(client, *replies):
    fake = FakeProvider("gemini", list(replies))
    client.app.state.ai = AIService([fake], retry_delay=0)
    return fake


def test_needs_mental_health_consent(registered):
    client, tokens = registered
    r = client.post("/mental/companion/chat", headers=auth_header(tokens), json={"message": "hi"})
    assert r.status_code == 403


def test_chat_reads_state_and_saves_history(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _consent(client, tokens)
    _ai(client, _out("Exams can feel like a lot. It makes sense you feel stretched."), _out("Glad that helped."))
    r = client.post("/mental/companion/chat", headers=h,
                    json={"message": "exams ki wajah se bohat stress hai", "language": "roman_ur", "mood": "Stressed"}).json()
    assert r["crisis"] is False and r["tone"] == "overwhelmed" and r["coping_tip"]
    r2 = client.post("/mental/companion/chat", headers=h, json={"message": "thanks", "chat_id": r["chat_id"]}).json()
    assert r2["chat_id"] == r["chat_id"]
    chat = client.get(f"/mental/companion/chats/{r['chat_id']}", headers=h).json()
    assert chat["mood"] == "Stressed" and len(chat["turns"]) == 2
    ins = client.get("/mental/companion/insights", headers=h).json()
    assert ins["tones"][0]["tone"] == "overwhelmed" and ins["themes"][0]["theme"] == "stress"


def test_crisis_words_skip_ai_and_show_helplines(registered):
    client, tokens = registered
    _consent(client, tokens)
    fake = _ai(client)
    r = client.post("/mental/companion/chat", headers=auth_header(tokens),
                    json={"message": "mujhe ab zinda nahi rehna", "language": "roman_ur"}).json()
    assert fake.calls == 0 and r["crisis"] and "0317-4288665" in r["reply"]
    assert any(line["number"] == "0800-22-444" for line in r["crisis_lines"])


def test_ai_detected_high_risk_uses_crisis_reply(registered):
    client, tokens = registered
    _consent(client, tokens)
    _ai(client, _out("Some reply", crisis_risk="high", severity="severe"))
    r = client.post("/mental/companion/chat", headers=auth_header(tokens),
                    json={"message": "everything feels pointless lately"}).json()
    assert r["crisis"] and "Umang" in r["reply"]


def test_medicine_removed_from_reply(registered):
    client, tokens = registered
    _consent(client, tokens)
    _ai(client, _out("That sounds hard. You could take a sleeping tablet. Try a calm routine before bed."))
    r = client.post("/mental/companion/chat", headers=auth_header(tokens), json={"message": "can't sleep"}).json()
    assert "tablet" not in r["reply"] and "routine" in r["reply"]


def test_memory_compression_and_forget(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _consent(client, tokens)
    replies = [_out(f"reply {i}") for i in range(11)] + [json.dumps({"summary": "User is Sara, stressed by exams."})]
    _ai(client, *replies)
    chat_id = None
    for i in range(11):
        body = {"message": f"message {i}"}
        if chat_id:
            body["chat_id"] = chat_id
        chat_id = client.post("/mental/companion/chat", headers=h, json=body).json()["chat_id"]
    mem = client.get("/mental/companion/memory", headers=h).json()
    assert mem["summary"].startswith("User is Sara") and mem["turns"] == 11
    assert client.delete("/mental/companion/memory", headers=h).status_code == 204
    assert client.get("/mental/companion/memory", headers=h).json() == {"summary": "", "turns": 0, "updated_at": None}


def test_chats_private(registered):
    client, tokens = registered
    _consent(client, tokens)
    _ai(client, _out())
    cid = client.post("/mental/companion/chat", headers=auth_header(tokens), json={"message": "hi"}).json()["chat_id"]
    other = client.post("/auth/register", json={**VALID_USER, "email": "z@example.com"}).json()
    assert client.get(f"/mental/companion/chats/{cid}", headers=auth_header(other)).status_code == 404


def test_warning_signs_keep_reply_but_add_helpline(registered):
    client, tokens = registered
    _consent(client, tokens)
    _ai(client, _out("That sounds really heavy, Ali.", crisis_risk="low", emotional_tone="hopeless"))
    r = client.post("/mental/companion/chat", headers=auth_header(tokens),
                    json={"message": "kabhi lagta hai sab khatam ho jaye", "language": "roman_ur"}).json()
    assert not r["crisis"] and r["support_lines"]
    assert r["reply"].startswith("That sounds really heavy") and "0317-4288665" in r["reply"]
    assert r["crisis_lines"]
