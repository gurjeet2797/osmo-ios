from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.connectors.google_calendar import GoogleCalendarClient, credentials_from_encrypted
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.user import User

log = structlog.get_logger()

router = APIRouter()


@router.get("/upcoming")
async def upcoming_events(
    user: Annotated[User, Depends(get_current_user)],
    days: int = Query(default=1, ge=1, le=14),
):
    """Fetch upcoming events from the user's Google Calendar."""
    if not user.google_tokens_encrypted:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "No Google Calendar connected. Please sign in with Google first.",
        )

    creds = credentials_from_encrypted(user.google_tokens_encrypted)
    client = GoogleCalendarClient(creds)

    now = datetime.now(UTC)
    time_max = now + timedelta(days=days)

    try:
        raw_events = client.list_events(time_min=now, time_max=time_max)
    except Exception as e:
        log.error("calendar.upcoming.failed", error=str(e))
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"Failed to fetch calendar: {e}")

    events = []
    for ev in raw_events:
        start = ev.get("start", {})
        end = ev.get("end", {})
        events.append(
            {
                "id": ev.get("id", ""),
                "title": ev.get("summary", "(No title)"),
                "start": start.get("dateTime") or start.get("date", ""),
                "end": end.get("dateTime") or end.get("date", ""),
                "location": ev.get("location"),
                "all_day": "date" in start and "dateTime" not in start,
            }
        )

    return {"events": events}
