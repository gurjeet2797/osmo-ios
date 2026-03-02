from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import distinct, select

from app.config import settings
from app.db.session import async_session_factory, get_redis
from app.models.command_history import CommandHistory
from app.models.user import User
from app.models.user_preference import UserPreference

log = structlog.get_logger()

BRIEFING_TTL = 12 * 3600  # 12 hours


async def prepare_all_briefings() -> None:
    """Prepare morning briefings for all active users."""
    log.info("job.morning_briefings.start")

    async with async_session_factory() as db:
        cutoff = datetime.now(UTC) - timedelta(days=7)
        result = await db.execute(
            select(distinct(CommandHistory.user_id)).where(
                CommandHistory.created_at >= cutoff
            )
        )
        user_ids = [row[0] for row in result.all()]

        count = 0
        for user_id in user_ids:
            try:
                await prepare_morning_briefing(str(user_id))
                count += 1
            except Exception:
                log.warning("briefing.failed", user_id=str(user_id), exc_info=True)

    log.info("job.morning_briefings.done", count=count)


async def prepare_morning_briefing(user_id: str) -> str | None:
    """Generate a morning briefing for a user and cache in Redis."""
    async with async_session_factory() as db:
        # Load user info and preferences
        result = await db.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user:
            return None

        result = await db.execute(
            select(UserPreference)
            .where(UserPreference.user_id == user_id)
            .order_by(UserPreference.key)
        )
        prefs = {p.key: p.value for p in result.scalars().all()}

    # Build briefing prompt
    pref_text = ", ".join(f"{k}: {v}" for k, v in prefs.items()) if prefs else "none"
    user_tz = user.timezone or "UTC"
    user_name = user.name or "there"

    prompt = (
        f"Generate a short, friendly morning briefing for {user_name}. "
        f"Their timezone is {user_tz}. "
        f"Their preferences: {pref_text}. "
        f"Keep it to 2-3 sentences. Be warm and concise. "
        f"Mention what kind of day it looks like based on available context."
    )

    # Call LLM for briefing
    try:
        if settings.llm_provider == "anthropic":
            from anthropic import AsyncAnthropic
            client = AsyncAnthropic(api_key=settings.anthropic_api_key)
            response = await client.messages.create(
                model=settings.anthropic_model,
                max_tokens=256,
                messages=[{"role": "user", "content": prompt}],
            )
            briefing = response.content[0].text
        else:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.openai_api_key)
            response = await client.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {"role": "system", "content": "You are Osmo, a friendly AI assistant."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=256,
            )
            briefing = response.choices[0].message.content
    except Exception:
        log.warning("briefing.llm_failed", user_id=user_id, exc_info=True)
        return None

    # Cache in Redis
    redis = await get_redis()
    cache_key = f"briefing:{user_id}"
    await redis.setex(
        cache_key,
        BRIEFING_TTL,
        json.dumps({
            "briefing": briefing,
            "generated_at": datetime.now(UTC).isoformat(),
        }),
    )

    log.info("briefing.prepared", user_id=user_id)
    return briefing


async def get_cached_briefing(user_id: str) -> dict | None:
    """Retrieve a cached briefing from Redis."""
    redis = await get_redis()
    data = await redis.get(f"briefing:{user_id}")
    if data:
        return json.loads(data)
    return None
