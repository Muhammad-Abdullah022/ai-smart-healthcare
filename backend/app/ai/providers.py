"""AI provider clients.

Each provider takes a system instruction + user prompt and returns raw JSON text.
All providers share one interface (`AIProvider`), so features never depend on a
specific company. Keys are read from backend settings and never leave the server.
"""
from __future__ import annotations

import httpx


class AIProviderError(Exception):
    """Any provider failure: no key, network error, timeout, rate limit, bad reply."""

    def __init__(self, provider: str, message: str, retryable: bool = True):
        super().__init__(f"{provider}: {message}")
        self.provider = provider
        self.retryable = retryable


class AIProvider:
    name = "base"

    async def generate_json(self, system: str, prompt: str) -> str:
        raise NotImplementedError


def _check_status(provider: str, response: httpx.Response) -> None:
    if response.status_code == 429:
        raise AIProviderError(provider, "rate limit or quota reached")
    if response.status_code in (401, 403):
        raise AIProviderError(provider, "API key rejected", retryable=False)
    if response.status_code >= 400:
        raise AIProviderError(provider, f"HTTP {response.status_code}", retryable=response.status_code >= 500)


class GeminiProvider(AIProvider):
    """Google Gemini via the generateContent REST API, asking for JSON output."""

    name = "gemini"
    base_url = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(self, api_key: str, model: str, timeout: float, client: httpx.AsyncClient | None = None):
        self.api_key = api_key
        self.model = model
        self.timeout = timeout
        self._client = client

    async def generate_json(self, system: str, prompt: str) -> str:
        if not self.api_key:
            raise AIProviderError(self.name, "GEMINI_API_KEY is not set", retryable=False)
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
        }
        url = f"{self.base_url}/models/{self.model}:generateContent"
        data = await _post(self.name, url, body, {"x-goog-api-key": self.api_key}, self.timeout, self._client)
        try:
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError, TypeError):
            # Happens e.g. when the reply was blocked by Gemini's safety filters.
            raise AIProviderError(self.name, "reply had no text")


class GroqProvider(AIProvider):
    """Groq (OpenAI-compatible chat completions API) with JSON mode."""

    name = "groq"
    url = "https://api.groq.com/openai/v1/chat/completions"

    def __init__(self, api_key: str, model: str, timeout: float, client: httpx.AsyncClient | None = None):
        self.api_key = api_key
        self.model = model
        self.timeout = timeout
        self._client = client

    async def generate_json(self, system: str, prompt: str) -> str:
        if not self.api_key:
            raise AIProviderError(self.name, "GROQ_API_KEY is not set", retryable=False)
        body = {
            "model": self.model,
            "temperature": 0.2,
            "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": prompt}],
        }
        headers = {"Authorization": f"Bearer {self.api_key}"}
        data = await _post(self.name, self.url, body, headers, self.timeout, self._client)
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            raise AIProviderError(self.name, "reply had no text")


async def _post(provider: str, url: str, body: dict, headers: dict, timeout: float,
                client: httpx.AsyncClient | None) -> dict:
    owns_client = client is None
    client = client or httpx.AsyncClient()
    try:
        response = await client.post(url, json=body, headers=headers, timeout=timeout)
    except httpx.TimeoutException:
        raise AIProviderError(provider, "timed out")
    except httpx.HTTPError as exc:
        raise AIProviderError(provider, f"network error ({type(exc).__name__})")
    finally:
        if owns_client:
            await client.aclose()
    _check_status(provider, response)
    try:
        return response.json()
    except ValueError:
        raise AIProviderError(provider, "reply was not JSON")
