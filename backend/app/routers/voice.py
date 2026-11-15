"""Natural Urdu voice for the chatbots (Uplift AI text-to-speech).

The app sends the reply text; the backend (which holds the secret key) returns MP3 audio.
Roman Urdu is first written in Urdu script by the AI, because the voice reads Urdu script.
Audio is cached in memory so replaying a message does not use credits again.
"""
import hashlib
from collections import OrderedDict
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app.ai.service import AIUnavailableError
from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.rate_limit import limit_by_user
from app.deps import get_current_user
from app.routers.assessments import get_ai_service

router = APIRouter(prefix="/voice", tags=["voice"])
UPLIFT_URL = "https://api.upliftai.org/v1/synthesis/text-to-speech"
_cache: "OrderedDict[str, bytes]" = OrderedDict()
_CACHE_MAX = 200

URDU_SCRIPT_SYSTEM = """Rewrite the given Roman Urdu text in Urdu script (Nastaliq letters) with the same words and
meaning, so an Urdu voice can read it. Keep numbers as digits and keep English medical words in Urdu script
(e.g. ڈاکٹر، ٹیسٹ). Do not add or remove anything. Reply as JSON: {"urdu": "..."}"""


class UrduScript(BaseModel):
    urdu: str = Field(max_length=4000)


class TTSRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2400)
    language: Literal["ur", "roman_ur"] = "ur"


@router.get("/status")
async def voice_status(user: dict = Depends(get_current_user)):
    """Whether the natural Urdu voice is set up (the app falls back to the device voice if not)."""
    return {"urdu_voice": bool(get_settings().upliftai_api_key)}


@router.post("/tts", dependencies=[limit_by_user("voice_tts", 300, 3600)])
async def text_to_speech(body: TTSRequest, request: Request, user: dict = Depends(get_current_user)):
    settings = get_settings()
    if not settings.upliftai_api_key:
        raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "voice_not_configured", "Urdu voice is not set up.")
    key = hashlib.sha256(f"{body.language}|{settings.upliftai_voice_id}|{body.text}".encode()).hexdigest()
    if key in _cache:
        _cache.move_to_end(key)
        return Response(_cache[key], media_type="audio/mpeg", headers={"Cache-Control": "private, max-age=86400"})

    text = body.text
    if body.language == "roman_ur":
        try:
            text = (await get_ai_service(request).generate(UrduScript, URDU_SCRIPT_SYSTEM, body.text)).data.urdu
        except AIUnavailableError:
            raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "ai_unavailable", "Could not prepare the Urdu voice.")

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            r = await client.post(UPLIFT_URL, headers={"Authorization": f"Bearer {settings.upliftai_api_key}"},
                                  json={"voiceId": settings.upliftai_voice_id, "text": text[:2500],
                                        "outputFormat": "MP3_22050_64"})
    except httpx.HTTPError as exc:
        print(f"[voice] {exc}")
        raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "voice_unavailable", "The Urdu voice is not reachable.")
    if r.status_code != 200:
        msg = ""
        try:
            msg = r.json().get("message", "")
        except ValueError:
            pass
        print(f"[voice] Uplift HTTP {r.status_code}: {msg}")
        raise ApiError(status.HTTP_503_SERVICE_UNAVAILABLE, "voice_unavailable",
                       "The Urdu voice is busy right now." if r.status_code == 429 else "The Urdu voice failed.")
    _cache[key] = r.content
    if len(_cache) > _CACHE_MAX:
        _cache.popitem(last=False)
    return Response(r.content, media_type=r.headers.get("content-type", "audio/mpeg"),
                    headers={"Cache-Control": "private, max-age=86400"})
