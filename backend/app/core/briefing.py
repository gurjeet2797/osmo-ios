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

    # Build briefing prompt with real calendar data
    user_tz = user.timezone or "UTC"
    user_name = user.name or "there"
    first_name = user_name.split()[0] if user_name != "there" else "there"

    # Fetch today's calendar events for the briefing
    events_text = "No events today."
    try:
        if user.google_tokens_encrypted:
            from app.connectors.google_calendar import GoogleCalendarClient, credentials_from_encrypted
            from zoneinfo import ZoneInfo
            creds = credentials_from_encrypted(user.google_tokens_encrypted)
            cal_client = GoogleCalendarClient(creds)
            try:
                tz = ZoneInfo(user_tz)
            except (KeyError, ValueError):
                tz = ZoneInfo("UTC")
            now = datetime.now(tz)
            day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
            day_end = day_start + timedelta(days=1)
            today_events = cal_client.list_events(time_min=day_start, time_max=day_end, max_results=10)
            if today_events:
                lines = []
                for ev in today_events:
                    start = ev.get("start", {}).get("dateTime", ev.get("start", {}).get("date", ""))
                    summary = ev.get("summary", "Untitled")
                    # Extract just time portion
                    if "T" in start:
                        time_part = start.split("T")[1][:5]
                    else:
                        time_part = "all day"
                    lines.append(f"- {time_part}: {summary}")
                events_text = "\n".join(lines)
            else:
                events_text = "No events today — open schedule."
    except Exception:
        log.debug("briefing.calendar_fetch_failed", user_id=user_id, exc_info=True)

    # Fetch unread email count
    email_text = ""
    try:
        if user.google_tokens_encrypted:
            from app.connectors.google_gmail import GoogleGmailClient
            gmail_creds = credentials_from_encrypted(user.google_tokens_encrypted)
            gmail_client = GoogleGmailClient(gmail_creds)
            unread = gmail_client.search_messages("is:unread", max_results=1)
            unread_count = unread.get("result_count", 0) if isinstance(unread, dict) else len(unread) if isinstance(unread, list) else 0
            if unread_count > 0:
                email_text = f"\nUnread emails: {unread_count}."
    except Exception:
        log.debug("briefing.email_fetch_failed", user_id=user_id, exc_info=True)

    prompt = (
        f"Write a 2-sentence morning briefing for {first_name}. "
        f"Timezone: {user_tz}. No emoji. No filler.\n\n"
        f"Today's calendar:\n{events_text}{email_text}\n\n"
        f"Summarize what the day looks like based on the actual events. "
        f"If no events, note the open schedule briefly. Be direct and useful."
    )

    # Call LLM for briefing
    try:
        if settings.llm_provider == "anthropic":
            from anthropic import AsyncAnthropic
            client = AsyncAnthropic(api_key=settings.anthropic_api_key)
            response = await client.messages.create(
                model=settings.anthropic_model,
                max_tokens=150,
                system="You are Osmo, a concise personal assistant. No emoji. No filler.",
                messages=[{"role": "user", "content": prompt}],
            )
            briefing = response.content[0].text
        else:
            from openai import AsyncOpenAI
            client = AsyncOpenAI(api_key=settings.openai_api_key)
            response = await client.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {"role": "system", "content": "You are Osmo, a concise personal assistant. No emoji. No filler."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=150,
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
