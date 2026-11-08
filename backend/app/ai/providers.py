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

    supports_images = False

    async def generate_json(self, system: str, prompt: str, images: list[tuple[str, str]] | None = None) -> str:
        """images: list of (mime_type, base64_data)."""
        raise NotImplementedError


def _check_status(provider: str, response: httpx.Response) -> None:
    if response.status_code == 429:
        raise AIProviderError(provider, "rate limit or quota reached")
    if response.status_code in (401, 403):
        raise AIProviderError(provider, "API key rejected", retryable=False)
    if response.status_code >= 400:
        # Include the API's own short error text (e.g. "model not found") to make problems clear.
        detail = ""
        try:
            err = response.json().get("error", {})
            detail = (err.get("message") if isinstance(err, dict) else str(err)) or ""
        except (ValueError, AttributeError):
            pass
        raise AIProviderError(provider, f"HTTP {response.status_code}" + (f": {detail[:160]}" if detail else ""),
                              retryable=response.status_code >= 500)


class GeminiProvider(AIProvider):
    """Google Gemini via the generateContent REST API, asking for JSON output."""

    name = "gemini"
    supports_images = True
    base_url = "https://generativelanguage.googleapis.com/v1beta"

    def __init__(self, api_key: str, model: str, timeout: float, client: httpx.AsyncClient | None = None):
        self.api_key = api_key
        self.model = model
        self.timeout = timeout
        self._client = client

    async def generate_json(self, system: str, prompt: str, images: list[tuple[str, str]] | None = None) -> str:
        if not self.api_key:
            raise AIProviderError(self.name, "GEMINI_API_KEY is not set", retryable=False)
        parts = [{"inline_data": {"mime_type": m, "data": d}} for m, d in (images or [])] + [{"text": prompt}]
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": parts}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "temperature": 0.2,
                # "Thinking" made replies take 7-14 s (close to the time limit). These are short,
                # structured answers checked by our own safety rules, so it is switched off: ~2-4 s.
                **({"thinkingConfig": {"thinkingBudget": 0}} if "flash" in self.model else {}),
            },
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

    # Tried in order if the configured model is not available to this account (HTTP 404).
    BACKUP_MODELS = ("llama-3.3-70b-versatile", "openai/gpt-oss-120b", "openai/gpt-oss-20b", "llama-3.1-8b-instant")

    def __init__(self, api_key: str, model: str, timeout: float, client: httpx.AsyncClient | None = None):
        self.api_key = api_key
        # GROQ_MODEL may list several models separated by commas.
        configured = [m.strip() for m in model.split(",") if m.strip()]
        self.models = list(dict.fromkeys(configured + list(self.BACKUP_MODELS)))
        self.model = self.models[0]
        self.timeout = timeout
        self._client = client

    async def generate_json(self, system: str, prompt: str, images: list[tuple[str, str]] | None = None) -> str:
        if images:
            raise AIProviderError(self.name, "cannot read images", retryable=False)
        if not self.api_key:
            raise AIProviderError(self.name, "GROQ_API_KEY is not set", retryable=False)
        headers = {"Authorization": f"Bearer {self.api_key}"}
        while True:
            body = {
                "model": self.model,
                "temperature": 0.2,
                "response_format": {"type": "json_object"},
                "messages": [{"role": "system", "content": system}, {"role": "user", "content": prompt}],
            }
            try:
                data = await _post(self.name, self.url, body, headers, self.timeout, self._client)
                break
            except AIProviderError as exc:
                # Model missing for this account: switch to the next one and remember it.
                nxt = self.models.index(self.model) + 1
                if "HTTP 404" in str(exc) and nxt < len(self.models):
                    self.model = self.models[nxt]
                    continue
                raise
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
