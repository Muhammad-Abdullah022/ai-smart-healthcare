import json

import httpx

import app.routers.voice as voice
from app.ai.service import AIService
from app.core.config import get_settings
from tests.conftest import auth_header
from tests.test_ai import FakeProvider


def test_not_configured(registered, monkeypatch):
    client, tokens = registered
    monkeypatch.setattr(get_settings(), "upliftai_api_key", "")
    assert client.get("/voice/status", headers=auth_header(tokens)).json() == {"urdu_voice": False}
    r = client.post("/voice/tts", headers=auth_header(tokens), json={"text": "سلام"})
    assert r.status_code == 503


def test_roman_urdu_converted_then_spoken_and_cached(registered, monkeypatch):
    client, tokens = registered
    monkeypatch.setattr(get_settings(), "upliftai_api_key", "sk_api_test")
    voice._cache.clear()
    client.app.state.ai = AIService([FakeProvider("gemini", [json.dumps({"urdu": "آرام کریں"})])], retry_delay=0)
    calls = []

    class FakeClient:
        def __init__(self, *a, **k):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, url, headers=None, json=None):
            calls.append((headers, json))
            return httpx.Response(200, content=b"MP3DATA", headers={"content-type": "audio/mpeg"})

    monkeypatch.setattr(voice.httpx, "AsyncClient", FakeClient)
    h = auth_header(tokens)
    r = client.post("/voice/tts", headers=h, json={"text": "Aaram karein", "language": "roman_ur"})
    assert r.status_code == 200 and r.content == b"MP3DATA"
    assert calls[0][0]["Authorization"] == "Bearer sk_api_test" and calls[0][1]["text"] == "آرام کریں"
    client.post("/voice/tts", headers=h, json={"text": "Aaram karein", "language": "roman_ur"})
    assert len(calls) == 1  # second time from cache
