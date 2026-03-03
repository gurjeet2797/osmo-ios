"""
openclaw_briefing.py — Proactive intelligence features powered by OpenClaw.

These functions call the OpenClaw agent with structured prompts to generate
richer, multi-source responses that the one-shot local planner can't produce.
All functions fail gracefully (return None) if OpenClaw is unavailable.
"""

from __future__ import annotations

import logging
from typing import Any

from app.core.openclaw_client import openclaw_client

logger = logging.getLogger(__name__)


async def generate_morning_briefing(
    user_id: str,
    calendar_events: list[dict[str, Any]],
    preferences: str = "",
) -> str | None:
    """
    Generate a warm, concise morning briefing for the user based on their
    calendar and stored preferences.

    Args:
        user_id: Used as the OpenClaw session ID for context continuity.
        calendar_events: List of today's events (title, time, attendees).
        preferences: User preference string (timezone, communication style, etc.)

    Returns:
        A short briefing string, or None if OpenClaw is unavailable.
    """
    if not calendar_events:
        events_text = "No events scheduled for today."
    else:
        lines = []
        for ev in calendar_events:
            title = ev.get("title", "Untitled")
            start = ev.get("start_time", "")
            attendees = ev.get("attendees", [])
            att_str = f" with {', '.join(attendees)}" if attendees else ""
            lines.append(f"- {start}: {title}{att_str}")
        events_text = "\n".join(lines)

    prompt = f"""Morning briefing (3-5 sentences). Friendly, practical.

Calendar: {events_text}
Prefs: {preferences or 'None'}

Summarize the day, flag conflicts, close with encouragement. No bullets."""

    return await openclaw_client.send_message(
        text=prompt,
        session_id=f"osmo-briefing-{user_id}",
    )


async def generate_meeting_prep(
    meeting_title: str,
    attendees: list[str],
    user_id: str,
    notes: str = "",
) -> str | None:
    """
    Generate structured prep notes for an upcoming meeting.

    OpenClaw can web-search attendees, cross-reference past context, and
    return a structured briefing the local planner cannot produce in one shot.

    Args:
        meeting_title: Name/subject of the meeting.
        attendees: List of attendee names or emails.
        user_id: OpenClaw session ID for context continuity.
        notes: Any existing agenda or notes to incorporate.

    Returns:
        A structured markdown prep note, or None if OpenClaw is unavailable.
    """
    attendees_str = ", ".join(attendees) if attendees else "No attendees listed."

    prompt = f"""Meeting prep for: {meeting_title}
Attendees: {attendees_str}
Notes: {notes or 'None'}

Brief with: **Purpose**, **Attendees** (one line each), **Talking points** (3), **Open questions**, **Prior actions**. Fit on one screen."""

    return await openclaw_client.send_message(
        text=prompt,
        session_id=f"osmo-meeting-{user_id}",
    )


async def generate_task_summary(
    task_description: str,
    user_id: str,
    context: dict[str, Any] | None = None,
) -> str | None:
    """
    Delegate a complex multi-step task to OpenClaw and return its response.
    General-purpose entry point for tasks that don't fit a specific template.
    """
    return await openclaw_client.send_message(
        text=task_description,
        session_id=f"osmo-task-{user_id}",
        context=context,
    )


async def deep_research(
    topic: str,
    user_id: str,
    context: dict[str, Any] | None = None,
) -> str | None:
    """
    Perform deep research on a topic using web search and analysis.

    Returns structured markdown with findings, sources, and key takeaways.
    """
    prompt = f"""Research: {topic}

Use web search + knowledge. Return: **Key Findings** (3-5 points), **Analysis** (2-3 paragraphs), **Sources**, **Takeaways** (2-3 actionable). Thorough but concise."""

    return await openclaw_client.send_message(
        text=prompt,
        session_id=f"osmo-research-{user_id}",
        context=context,
    )


async def generate_review(
    period: str,
    user_id: str,
    calendar_events: list[dict[str, Any]] | None = None,
    command_history: list[str] | None = None,
    context: dict[str, Any] | None = None,
) -> str | None:
    """
    Generate a daily or weekly review from calendar events and command history.

    Args:
        period: "daily" or "weekly"
        user_id: OpenClaw session ID
        calendar_events: Events from the review period
        command_history: Recent commands/tasks from the period
        context: Additional context (timezone, preferences)
    """
    events_block = "No calendar data available."
    if calendar_events:
        lines = []
        for ev in calendar_events:
            title = ev.get("title", "Untitled")
            start = ev.get("start_time", "")
            lines.append(f"- {start}: {title}")
        events_block = "\n".join(lines)

    history_block = "No command history available."
    if command_history:
        history_block = "\n".join(f"- {cmd}" for cmd in command_history[:20])

    prompt = f"""{period.title()} review.

Calendar: {events_block}
Activity: {history_block}

Sections: **Accomplishments**, **Patterns**, **Unfinished Business**, **Suggestions** (1-2). Warm, honest, actionable. 4-6 paragraphs max."""

    return await openclaw_client.send_message(
        text=prompt,
        session_id=f"osmo-review-{user_id}",
        context=context,
    )


async def decision_analysis(
    decision: str,
    user_id: str,
    options: list[str] | None = None,
    context: dict[str, Any] | None = None,
) -> str | None:
    """
    Help the user think through a decision with structured pros/cons analysis.

    Args:
        decision: The decision to analyze
        user_id: OpenClaw session ID
        options: Explicit options to compare (if provided)
        context: Additional context
    """
    options_block = ""
    if options:
        options_block = "\nExplicit options to compare:\n" + "\n".join(
            f"- {opt}" for opt in options
        )

    prompt = f"""Decision analysis: {decision}
{options_block}

Sections: **Options** (list or infer 2-3), **Pros & Cons** (2-3 each), **Key Considerations**, **Recommendation**, **Next Steps** (1-2). Balanced and practical."""

    return await openclaw_client.send_message(
        text=prompt,
        session_id=f"osmo-decision-{user_id}",
        context=context,
    )
