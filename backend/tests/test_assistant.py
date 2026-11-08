import json

from app.ai.service import AIService
from tests.conftest import VALID_USER, auth_header
from tests.test_ai import FakeProvider


def _ai(client, *replies):
    fake = FakeProvider("gemini", list(replies))
    client.app.state.ai = AIService([fake], retry_delay=0)
    return fake


def test_chat_saves_history_and_continues(registered):
    client, tokens = registered
    h = auth_header(tokens)
    _ai(client, json.dumps({"reply": "Diabetes means high blood sugar.", "suggest_symptom_check": False}),
        json.dumps({"reply": "Walking daily helps.", "suggest_symptom_check": False}))
    first = client.post("/assistant/chat", headers=h, json={"message": "What is diabetes?", "language": "en"}).json()
    assert first["reply"]["text"].startswith("Diabetes")
    second = client.post("/assistant/chat", headers=h,
                         json={"message": "How to prevent it?", "chat_id": first["chat_id"]}).json()
    assert second["chat_id"] == first["chat_id"]
    chats = client.get("/assistant/chats", headers=h).json()
    assert chats[0]["title"] == "What is diabetes?" and chats[0]["messages"] == 4
    full = client.get(f"/assistant/chats/{first['chat_id']}", headers=h).json()
    assert [m["role"] for m in full["messages"]] == ["user", "assistant", "user", "assistant"]


def test_emergency_words_answered_without_ai_in_urdu(registered):
    client, tokens = registered
    fake = _ai(client)
    r = client.post("/assistant/chat", headers=auth_header(tokens),
                    json={"message": "seene mein dard ho raha hai", "language": "roman_ur"}).json()
    assert fake.calls == 0 and r["reply"]["emergency"] is True and "1122" in r["reply"]["text"]


def test_chats_are_private(registered):
    client, tokens = registered
    _ai(client, json.dumps({"reply": "ok", "suggest_symptom_check": False}))
    cid = client.post("/assistant/chat", headers=auth_header(tokens), json={"message": "hi"}).json()["chat_id"]
    other = client.post("/auth/register", json={**VALID_USER, "email": "p@example.com"}).json()
    assert client.get(f"/assistant/chats/{cid}", headers=auth_header(other)).status_code == 404
    assert client.post("/assistant/chat", headers=auth_header(other),
                       json={"message": "x", "chat_id": cid}).status_code == 404
