"""OpenAI Whisper speech-to-text connector.

Supports 57+ languages with automatic language detection.
"""
from __future__ import annotations

import structlog
from openai import AsyncOpenAI

from app.config import settings

log = structlog.get_logger()


async def transcribe_audio(
    audio_data: bytes,
    filename: str = "audio.m4a",
    prompt: str | None = None,
) -> dict:
    """Transcribe audio bytes using OpenAI Whisper.

    Returns dict with keys: text, language, duration (if available).
    Language is auto-detected by Whisper.
    """
    client = AsyncOpenAI(api_key=settings.openai_api_key)

    response = await client.audio.transcriptions.create(
        model="whisper-1",
        file=(filename, audio_data),
        response_format="verbose_json",
        prompt=prompt,
    )

    result = {
        "text": response.text,
        "language": getattr(response, "language", None),
        "duration": getattr(response, "duration", None),
    }

    log.info(
        "whisper.transcribed",
        language=result["language"],
        duration=result["duration"],
        text_length=len(result["text"]),
    )

    return result
