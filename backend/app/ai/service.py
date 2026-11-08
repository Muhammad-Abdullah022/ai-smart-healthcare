"""Shared AI service: picks a provider, retries, falls back, and validates the reply.

Features call `AIService.generate(schema, system, prompt)` and get back a validated
Pydantic object — or an `AIUnavailableError` with a friendly message. They never
see raw AI text, so malformed replies can't reach the user.
"""
from __future__ import annotations

import asyncio
import json
import logging
from typing import TypeVar

from pydantic import BaseModel, ValidationError

from app.ai.providers import AIProvider, AIProviderError, GeminiProvider, GroqProvider
from app.core.config import Settings

log = logging.getLogger("ai")
T = TypeVar("T", bound=BaseModel)


class AIUnavailableError(Exception):
    """Every provider failed. The message is safe to show to users."""

    message = "The AI assistant is not available right now. Please try again in a few minutes."


class AIResult:
    def __init__(self, data: BaseModel, provider: str):
        self.data = data
        self.provider = provider


class AIService:
    def __init__(self, providers: list[AIProvider], attempts_per_provider: int = 1, retry_delay: float = 1.0):
        self.providers = providers
        self.attempts = attempts_per_provider
        self.retry_delay = retry_delay

    @classmethod
    def from_settings(cls, settings: Settings) -> "AIService":
        available = {
            "gemini": GeminiProvider(settings.gemini_api_key, settings.gemini_model, settings.ai_timeout_seconds),
            "groq": GroqProvider(settings.groq_api_key, settings.groq_model, settings.ai_timeout_seconds),
        }
        order = [settings.ai_primary, settings.ai_fallback]
        providers = [available[name] for name in dict.fromkeys(order) if name in available]
        return cls(providers)

    async def generate(self, schema: type[T], system: str, prompt: str) -> AIResult:
        """Try each provider in order; validate the JSON against `schema`."""
        system = system + "\n\nReply with ONE JSON object only, matching this JSON schema:\n" + json.dumps(
            schema.model_json_schema()
        )
        for provider in self.providers:
            for attempt in range(1, self.attempts + 1):
                try:
                    raw = await provider.generate_json(system, prompt)
                    return AIResult(schema.model_validate_json(_strip_fences(raw)), provider.name)
                except AIProviderError as exc:
                    log.warning("AI provider failed: %s (attempt %s)", exc, attempt)
                    print(f"[AI] {exc}")  # visible in the backend window
                    if not exc.retryable:
                        break
                except ValidationError as exc:
                    # The AI replied, but not in the shape we need: ask again.
                    log.warning("AI reply from %s failed validation: %s", provider.name, exc.error_count())
                if attempt < self.attempts:
                    await asyncio.sleep(self.retry_delay * attempt)
        raise AIUnavailableError()


def _strip_fences(text: str) -> str:
    """Some models wrap JSON in ```json fences; remove them."""
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else ""
        text = text.rsplit("```", 1)[0]
    return text.strip()
