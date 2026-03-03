"""
openclaw.py — FastAPI router for OpenClaw-powered endpoints.

Exposes proactive features (morning briefing, meeting prep, research, review,
decision analysis) and a health check so the iOS app can display OpenClaw
integration status.

Mount in main.py with:
    from app.api.openclaw import router as openclaw_router
    app.include_router(openclaw_router, prefix="/openclaw", tags=["openclaw"])
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends

from app.core.openclaw_briefing import (
    decision_analysis,
    deep_research,
    generate_meeting_prep,
    generate_morning_briefing,
    generate_review,
)
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


@router.post("/research")
async def research_endpoint(
    body: dict[str, Any],
    user: Annotated[User, Depends(get_current_user)],
) -> dict[str, Any]:
    """
    Deep research on a topic via OpenClaw.

    Expected body:
    {
        "topic": "quantum computing applications in finance",
        "context": {}  // optional additional context
    }
    """
    topic: str = body.get("topic", "")
    if not topic:
        return {"result": None, "generated": False, "error": "topic is required"}

    context: dict[str, Any] = body.get("context", {})
    context.setdefault("timezone", user.timezone)

    result = await deep_research(
        topic=topic,
        user_id=str(user.id),
        context=context,
    )

    return {
        "result": result,
        "generated": result is not None,
    }


@router.post("/review")
async def review_endpoint(
    body: dict[str, Any],
    user: Annotated[User, Depends(get_current_user)],
) -> dict[str, Any]:
    """
    Generate a daily or weekly review via OpenClaw.

    Expected body:
    {
        "period": "daily" | "weekly",
        "events": [{"title": "...", "start_time": "..."}],
        "command_history": ["researched X", "scheduled Y"]
    }
    """
    period: str = body.get("period", "daily")
    events: list[dict[str, Any]] = body.get("events", [])
    history: list[str] = body.get("command_history", [])
    context: dict[str, Any] = body.get("context", {})
    context.setdefault("timezone", user.timezone)

    result = await generate_review(
        period=period,
        user_id=str(user.id),
        calendar_events=events,
        command_history=history,
        context=context,
    )

    return {
        "result": result,
        "generated": result is not None,
    }


@router.post("/decision")
async def decision_endpoint(
    body: dict[str, Any],
    user: Annotated[User, Depends(get_current_user)],
) -> dict[str, Any]:
    """
    Decision analysis helper via OpenClaw.

    Expected body:
    {
        "decision": "Should I switch to a standing desk?",
        "options": ["Standing desk", "Sit-stand converter", "Stay seated"],  // optional
        "context": {}  // optional
    }
    """
    decision: str = body.get("decision", "")
    if not decision:
        return {"result": None, "generated": False, "error": "decision is required"}

    options: list[str] = body.get("options", [])
    context: dict[str, Any] = body.get("context", {})
    context.setdefault("timezone", user.timezone)

    result = await decision_analysis(
        decision=decision,
        user_id=str(user.id),
        options=options or None,
        context=context,
    )

    return {
        "result": result,
        "generated": result is not None,
    }
