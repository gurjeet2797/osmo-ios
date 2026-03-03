"""Intelligent data indexer — scans Gmail for flights, hotels, packages, etc."""

from __future__ import annotations

import json
from datetime import datetime

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.connectors.google_calendar import credentials_from_encrypted
from app.connectors.google_gmail import GoogleGmailClient
from app.db.session import async_session_factory
from app.models.indexed_event import IndexedEvent
from app.models.user import User

log = structlog.get_logger()

_GMAIL_QUERIES = [
    '"flight confirmation" OR "boarding pass" OR "itinerary" newer_than:14d',
    '"hotel reservation" OR "hotel confirmation" OR "check-in" newer_than:14d',
    '"package shipped" OR "tracking number" OR "out for delivery" newer_than:7d',
]

_EXTRACTION_SYSTEM_PROMPT = """\
You are a structured data extractor. Given an email body, extract any actionable event \
(flight, hotel booking, package delivery, car rental, restaurant reservation, etc.).

Return a JSON object with these fields:
- event_type: one of "flight", "hotel", "package", "car_rental", "restaurant", "event", "other"
- title: short summary (e.g. "Flight AA1234 SFO→JFK")
- date: ISO 8601 datetime of the event (e.g. "2026-03-15T14:30:00")
- location: address or airport code if applicable, or null
- details: object with relevant fields (airline, flight_number, confirmation_code, \
tracking_number, hotel_name, check_in, check_out, etc.)

If the email does not contain an actionable event, return exactly: null

Return ONLY valid JSON, no markdown fences or explanation."""


async def index_user_data() -> None:
    """Cron entry point: index Gmail data for all active Google users."""
    log.info("indexer.start")
    async with async_session_factory() as db:
        result = await db.execute(
            select(User).where(User.google_tokens_encrypted.isnot(None))
        )
        users = result.scalars().all()
        log.info("indexer.users_found", count=len(users))

        for user in users:
            try:
                count = await _index_user_gmail(db, user)
                log.info("indexer.user_done", user_id=str(user.id), events_indexed=count)
            except Exception:
                log.warning("indexer.user_failed", user_id=str(user.id), exc_info=True)

    log.info("indexer.done")


async def _index_user_gmail(db: AsyncSession, user: User) -> int:
    """Scan a single user's Gmail and index actionable events. Returns count of new events."""
    creds = credentials_from_encrypted(user.google_tokens_encrypted)
    gmail = GoogleGmailClient(creds)
    indexed_count = 0

    for query in _GMAIL_QUERIES:
        try:
            messages = gmail.search_messages(query, max_results=10)
        except Exception:
            log.warning("indexer.search_failed", user_id=str(user.id), query=query, exc_info=True)
            continue

        for msg_meta in messages:
            message_id = msg_meta["message_id"]

            # Check if already indexed
            existing = await db.execute(
                select(IndexedEvent.id).where(
                    IndexedEvent.user_id == user.id,
                    IndexedEvent.source == "gmail",
                    IndexedEvent.source_id == message_id,
                )
            )
            if existing.scalar_one_or_none() is not None:
                continue

            # Fetch full message
            try:
                full_msg = gmail.get_message(message_id)
            except Exception:
                log.warning("indexer.get_message_failed", message_id=message_id, exc_info=True)
                continue

            body = full_msg.get("body", "")
            subject = full_msg.get("subject", "")
            if not body:
                continue

            # Extract structured data via LLM
            extracted = await _extract_event(subject, body)
            if extracted is None:
                continue

            try:
                event = IndexedEvent(
                    user_id=user.id,
                    source="gmail",
                    source_id=message_id,
                    event_type=extracted.get("event_type", "other"),
                    title=extracted.get("title", subject)[:512],
                    details=extracted.get("details", {}),
                    event_date=datetime.fromisoformat(extracted["date"]),
                    location=extracted.get("location"),
                )
                db.add(event)
                indexed_count += 1
            except (KeyError, ValueError):
                log.warning("indexer.parse_failed", message_id=message_id, exc_info=True)
                continue

    await db.commit()
    return indexed_count


async def _extract_event(subject: str, body: str) -> dict | None:
    """Use LLM to extract structured event data from an email."""
    # Truncate body to keep tokens low
    truncated_body = body[:4000]
    user_message = f"Subject: {subject}\n\nBody:\n{truncated_body}"

    try:
        if settings.llm_provider == "anthropic":
            return await _extract_anthropic(user_message)
        else:
            return await _extract_openai(user_message)
    except Exception:
        log.warning("indexer.llm_extract_failed", exc_info=True)
        return None


async def _extract_openai(user_message: str) -> dict | None:
    import openai

    client = openai.AsyncOpenAI(api_key=settings.openai_api_key)
    response = await client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": _EXTRACTION_SYSTEM_PROMPT},
            {"role": "user", "content": user_message},
        ],
        temperature=0,
        max_tokens=512,
    )
    text = response.choices[0].message.content or ""
    text = text.strip()
    if text.lower() == "null":
        return None
    return json.loads(text)


async def _extract_anthropic(user_message: str) -> dict | None:
    import anthropic

    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
    response = await client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=512,
        system=_EXTRACTION_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
    )
    text = response.content[0].text.strip()
    if text.lower() == "null":
        return None
    return json.loads(text)
