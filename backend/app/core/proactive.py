"""Proactive notification generator — creates notifications for upcoming indexed events."""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import async_session_factory
from app.models.indexed_event import IndexedEvent
from app.models.proactive_notification import ProactiveNotification

log = structlog.get_logger()

_NOTIFICATION_PROMPT = """\
You are a helpful assistant generating a proactive notification for a user. \
Given an upcoming event, generate a friendly, concise notification.

Return a JSON object with:
- title: short notification title (max 50 chars, e.g. "Flight Tomorrow")
- body: friendly notification body (1-2 sentences, e.g. "Your flight AA1234 to JFK departs at 2:30 PM. Don't forget your passport!")
- suggested_actions: list of 1-3 suggested follow-up actions (e.g. ["check flight status", "set departure reminder", "get directions to airport"])

Return ONLY valid JSON, no markdown fences or explanation."""


async def generate_proactive_notifications() -> None:
    """Cron entry point: generate notifications for events in the next 24 hours."""
    log.info("proactive.start")
    now = datetime.now(UTC)
    window_end = now + timedelta(hours=24)

    async with async_session_factory() as db:
        # Find events in the next 24 hours that haven't been notified
        result = await db.execute(
            select(IndexedEvent).where(
                and_(
                    IndexedEvent.event_date >= now,
                    IndexedEvent.event_date <= window_end,
                    IndexedEvent.notified == False,  # noqa: E712
                )
            )
        )
        events = result.scalars().all()
        log.info("proactive.events_found", count=len(events))

        # Group by user
        by_user: dict[str, list[IndexedEvent]] = {}
        for event in events:
            uid = str(event.user_id)
            by_user.setdefault(uid, []).append(event)

        for user_id, user_events in by_user.items():
            try:
                count = await _generate_for_user(db, user_events)
                log.info("proactive.user_done", user_id=user_id, notifications=count)
            except Exception:
                log.warning("proactive.user_failed", user_id=user_id, exc_info=True)

        await db.commit()

    log.info("proactive.done")


async def _generate_for_user(db: AsyncSession, events: list[IndexedEvent]) -> int:
    """Generate notifications for a single user's upcoming events."""
    count = 0
    for event in events:
        notification_data = await _generate_notification(event)
        if notification_data is None:
            continue

        # Determine fire_at: evening before (7 PM local) or morning-of (8 AM)
        # For simplicity, use 12 hours before the event, clamped to reasonable hours
        fire_at = event.event_date - timedelta(hours=12)
        now = datetime.now(UTC)
        if fire_at < now:
            fire_at = now  # Fire immediately if within 12 hours

        notification = ProactiveNotification(
            user_id=event.user_id,
            event_id=event.id,
            title=notification_data.get("title", f"Upcoming: {event.title}")[:256],
            body=notification_data.get("body", event.title),
            suggested_actions=notification_data.get("suggested_actions", []),
            fire_at=fire_at,
        )
        db.add(notification)

        # Mark event as notified
        event.notified = True
        count += 1

    return count


async def _generate_notification(event: IndexedEvent) -> dict | None:
    """Use LLM to generate a friendly notification for an event."""
    event_info = (
        f"Event type: {event.event_type}\n"
        f"Title: {event.title}\n"
        f"Date: {event.event_date.isoformat()}\n"
        f"Location: {event.location or 'N/A'}\n"
        f"Details: {json.dumps(event.details)}"
    )

    try:
        if settings.llm_provider == "anthropic":
            return await _generate_anthropic(event_info)
        else:
            return await _generate_openai(event_info)
    except Exception:
        log.warning("proactive.llm_generate_failed", exc_info=True)
        return None


async def _generate_openai(event_info: str) -> dict | None:
    import openai

    client = openai.AsyncOpenAI(api_key=settings.openai_api_key)
    response = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": _NOTIFICATION_PROMPT},
            {"role": "user", "content": event_info},
        ],
        temperature=0.7,
        max_tokens=256,
    )
    text = response.choices[0].message.content or ""
    return json.loads(text.strip())


async def _generate_anthropic(event_info: str) -> dict | None:
    import anthropic

    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
    response = await client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=256,
        system=_NOTIFICATION_PROMPT,
        messages=[{"role": "user", "content": event_info}],
    )
    text = response.content[0].text.strip()
    return json.loads(text)
