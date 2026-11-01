import asyncio
import json

import httpx
import pytest

from app.ai.providers import AIProvider, AIProviderError, GeminiProvider, GroqProvider
from app.ai.safety import check_red_flags, remove_dosing
from app.ai.service import AIService, AIUnavailableError
from app.models.assessment import AISymptomOutput

GOOD = {
    "possible_causes": [{"name": "Common cold", "likelihood": "high", "reason": "Runny nose and mild fever."}],
    "triage_level": "routine",
    "triage_reason": "Mild symptoms.",
    "next_steps": ["Rest and drink fluids."],
}


def run(coro):
    return asyncio.run(coro)


# ---------- Provider clients (no real network: httpx MockTransport) ----------

def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


def test_gemini_request_and_parsing():
    seen = {}

    def handler(request: httpx.Request):
        seen["url"] = str(request.url)
        seen["key"] = request.headers.get("x-goog-api-key")
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": '{"a": 1}'}]}}]})

    provider = GeminiProvider("KEY", "gemini-test", 5, client=_client(handler))
    assert run(provider.generate_json("sys", "hi")) == '{"a": 1}'
    assert seen["url"].endswith("/models/gemini-test:generateContent")
    assert seen["key"] == "KEY"
    assert seen["body"]["generationConfig"]["responseMimeType"] == "application/json"


def test_groq_request_and_parsing():
    def handler(request: httpx.Request):
        assert request.headers["Authorization"] == "Bearer KEY"
        assert json.loads(request.content)["response_format"] == {"type": "json_object"}
        return httpx.Response(200, json={"choices": [{"message": {"content": '{"b": 2}'}}]})

    provider = GroqProvider("KEY", "llama", 5, client=_client(handler))
    assert run(provider.generate_json("sys", "hi")) == '{"b": 2}'


@pytest.mark.parametrize("status,retryable", [(429, True), (500, True), (401, False), (400, False)])
def test_provider_http_errors(status, retryable):
    provider = GroqProvider("KEY", "m", 5, client=_client(lambda r: httpx.Response(status, json={})))
    with pytest.raises(AIProviderError) as err:
        run(provider.generate_json("s", "p"))
    assert err.value.retryable is retryable


def test_provider_timeout():
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    provider = GeminiProvider("KEY", "m", 5, client=_client(handler))
    with pytest.raises(AIProviderError, match="timed out"):
        run(provider.generate_json("s", "p"))


def test_missing_key_is_not_retried():
    with pytest.raises(AIProviderError) as err:
        run(GeminiProvider("", "m", 5).generate_json("s", "p"))
    assert err.value.retryable is False


# ---------- AIService: validation, retry, fallback ----------

class FakeProvider(AIProvider):
    def __init__(self, name, replies):
        self.name = name
        self.replies = list(replies)
        self.calls = 0

    async def generate_json(self, system, prompt):
        self.calls += 1
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply


def test_valid_reply_returned():
    fake = FakeProvider("gemini", [json.dumps(GOOD)])
    result = run(AIService([fake], retry_delay=0).generate(AISymptomOutput, "s", "p"))
    assert result.provider == "gemini"
    assert result.data.triage_level == "routine"


def test_code_fences_are_stripped():
    fake = FakeProvider("gemini", ["```json\n" + json.dumps(GOOD) + "\n```"])
    assert run(AIService([fake], retry_delay=0).generate(AISymptomOutput, "s", "p")).data


def test_malformed_reply_retried_then_succeeds():
    fake = FakeProvider("gemini", ['{"triage_level": "maybe"}', json.dumps(GOOD)])
    result = run(AIService([fake], retry_delay=0).generate(AISymptomOutput, "s", "p"))
    assert fake.calls == 2 and result.data.possible_causes[0].name == "Common cold"


def test_falls_back_to_second_provider():
    primary = FakeProvider("gemini", [AIProviderError("gemini", "down"), AIProviderError("gemini", "down")])
    backup = FakeProvider("groq", [json.dumps(GOOD)])
    result = run(AIService([primary, backup], retry_delay=0).generate(AISymptomOutput, "s", "p"))
    assert result.provider == "groq"


def test_bad_key_skips_straight_to_fallback():
    primary = FakeProvider("gemini", [AIProviderError("gemini", "key", retryable=False)])
    backup = FakeProvider("groq", [json.dumps(GOOD)])
    run(AIService([primary, backup], retry_delay=0).generate(AISymptomOutput, "s", "p"))
    assert primary.calls == 1


def test_all_providers_fail():
    a = FakeProvider("gemini", ["not json", "still not json"])
    b = FakeProvider("groq", [AIProviderError("groq", "x"), AIProviderError("groq", "x")])
    with pytest.raises(AIUnavailableError):
        run(AIService([a, b], retry_delay=0).generate(AISymptomOutput, "s", "p"))


# ---------- Safety rules ----------

@pytest.mark.parametrize("text", [
    "I have chest pain since morning",
    "difficulty breathing after walking",
    "mujhe seene mein dard hai",
    "saans lene mein takleef",
    "I want to kill myself",
    "my child had a seizure",
])
def test_red_flags_detected(text):
    result = check_red_flags(text)
    assert result is not None and result.level == "critical"


@pytest.mark.parametrize("text", [
    "runny nose and mild cough",
    "the benefits of exercise",  # "fits" inside "benefits" must not match
    "headache for two days",
])
def test_no_false_red_flags(text):
    assert check_red_flags(text) is None


def test_urgent_flag_level():
    assert check_red_flags("worst headache of my life").level == "urgent"


def test_dosing_removed():
    kept = remove_dosing(["Rest well", "Take 500 mg paracetamol", "Drink 2 tablets daily", "See a doctor"])
    assert kept == ["Rest well", "See a doctor"]
