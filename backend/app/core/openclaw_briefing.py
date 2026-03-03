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

    prompt = f"""You are Osmo, a warm and concise personal assistant.
Generate a brief morning briefing (3-5 sentences max) for the user.
Keep it friendly, practical, and scannable.

Today's calendar:
{events_text}

User preferences: {preferences or 'No preferences stored.'}

Give a quick summary of the day ahead, any conflicts or busy periods to flag,
and one encouraging note to close. Do not use bullet points — write naturally."""

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

    prompt = f"""You are Osmo preparing a meeting briefing for the user.

Meeting: {meeting_title}
Attendees: {attendees_str}
Existing notes: {notes or 'None.'}

Provide a concise meeting prep brief with:
1. **Purpose** — likely goal of this meeting (infer if not stated)
2. **Attendees** — one line per person with role/context if known
3. **Key talking points** — 3 bullet points to drive the conversation
4. **Open questions** — what the user might want to clarify
5. **Action items from last time** — if any context is available

Keep it tight. This should fit on one screen."""

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
