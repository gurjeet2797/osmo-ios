"""
openclaw.py — FastAPI router for OpenClaw-powered endpoints.

Exposes proactive features (morning briefing, meeting prep) and a health
check so the iOS app can display OpenClaw integration status.

Mount in main.py with:
    from app.api.openclaw import router as openclaw_router
    app.include_router(openclaw_router, prefix="/openclaw", tags=["openclaw"])
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends

from app.core.openclaw_briefing import generate_meeting_prep, generate_morning_briefing
from app.core.openclaw_client import openclaw_client
from app.dependencies import get_current_user
from app.models.user import User

router = APIRouter()


@router.get("/status")
async def openclaw_status(
    _user: Annotated[User, Depends(get_current_user)],
) -> dict[str, Any]:
    """Check whether OpenClaw is configured and reachable."""
    return await openclaw_client.health_check()


@router.post("/briefing")
async def morning_briefing(
    body: dict[str, Any],
    user: Annotated[User, Depends(get_current_user)],
) -> dict[str, Any]:
    """
    Generate a morning briefing via OpenClaw.

    Expected body:
    {
        "events": [{"title": "...", "start_time": "09:00", "attendees": ["..."]}],
        "preferences": "optional preference string"
    }
    """
    events: list[dict[str, Any]] = body.get("events", [])
    preferences: str = body.get("preferences", "")

    briefing = await generate_morning_briefing(
        user_id=str(user.id),
        calendar_events=events,
        preferences=preferences,
    )

    return {
        "briefing": briefing,
        "generated": briefing is not None,
    }


@router.post("/meeting-prep")
async def meeting_prep(
    body: dict[str, Any],
    user: Annotated[User, Depends(get_current_user)],
) -> dict[str, Any]:
    """
    Generate structured meeting prep notes via OpenClaw.

    Expected body:
    {
        "meeting_title": "Q1 Review",
        "attendees": ["Alice", "Bob"],
        "notes": "optional existing agenda"
    }
    """
    title: str = body.get("meeting_title", "Untitled Meeting")
    attendees: list[str] = body.get("attendees", [])
    notes: str = body.get("notes", "")

    prep = await generate_meeting_prep(
        meeting_title=title,
        attendees=attendees,
        user_id=str(user.id),
        notes=notes,
    )

    return {
        "prep": prep,
        "generated": prep is not None,
    }
