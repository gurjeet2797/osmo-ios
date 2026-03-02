from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Annotated, Any

import structlog
from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.command_history import CommandHistory
from app.models.user import User

log = structlog.get_logger()

router = APIRouter()

_DEFAULT_SUGGESTIONS = [
    "What's on my calendar today?",
    "Schedule a meeting tomorrow at 2pm",
    "Find free time this week",
    "Show my upcoming events",
    "Cancel my next meeting",
]

# Time-based defaults when no history
_TIME_SUGGESTIONS: dict[str, list[str]] = {
    "morning": [
        "What's on my calendar today?",
        "Summarize my morning schedule",
        "When is my first meeting?",
    ],
    "afternoon": [
        "What's left on my calendar today?",
        "Schedule something for tomorrow",
        "Am I free at 3pm?",
    ],
    "evening": [
        "What's on my calendar tomorrow?",
        "Show my schedule for the week",
        "Cancel my last meeting",
    ],
}


def _time_of_day(hour: int) -> str:
    if hour < 12:
        return "morning"
    if hour < 17:
        return "afternoon"
    return "evening"


@router.get("")
async def get_suggestions(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    now = datetime.now(UTC)
    tod = _time_of_day(now.hour)

    # Query recent command history (last 14 days)
    cutoff = now - timedelta(days=14)
    result = await db.execute(
        select(CommandHistory)
        .where(
            CommandHistory.user_id == str(user.id),
            CommandHistory.created_at >= cutoff,
        )
        .order_by(CommandHistory.created_at.desc())
        .limit(100)
    )
    history = result.scalars().all()

    if len(history) < 5:
        # Not enough data — return time-based defaults
        return {"suggestions": _TIME_SUGGESTIONS.get(tod, _DEFAULT_SUGGESTIONS)}

    # Analyze patterns: find most common tool names for the current time of day
    current_hour = now.hour
    hour_range = range(max(0, current_hour - 2), min(24, current_hour + 3))
    time_relevant = [h for h in history if h.hour_of_day in hour_range]

    # Extract common transcripts/patterns
    suggestions: list[str] = []

    # Most common tool-based actions at this time
    tool_counts: dict[str, int] = {}
    for h in time_relevant:
        if h.tool_names:
            for t in h.tool_names:
                tool_counts[t] = tool_counts.get(t, 0) + 1

    # Map tool names to suggestion templates
    tool_suggestions = {
        "google_calendar.list_events": "What's on my calendar today?",
        "google_calendar.create_event": "Schedule a meeting",
        "google_calendar.delete_event": "Cancel a meeting",
        "google_calendar.update_event": "Reschedule a meeting",
        "google_calendar.free_busy": "When am I free?",
        "web_search.search": "Search the web for...",
        "google_gmail.list_messages": "Check my email",
    }

    for tool_name, _ in sorted(tool_counts.items(), key=lambda x: -x[1]):
        if tool_name in tool_suggestions and len(suggestions) < 5:
            s = tool_suggestions[tool_name]
            if s not in suggestions:
                suggestions.append(s)

    # Pad with time-based defaults if needed
    if len(suggestions) < 5:
        for s in _TIME_SUGGESTIONS.get(tod, _DEFAULT_SUGGESTIONS):
            if s not in suggestions and len(suggestions) < 5:
                suggestions.append(s)

    return {"suggestions": suggestions[:5]}
