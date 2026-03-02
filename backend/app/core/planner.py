from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.config import settings
from app.tools.registry import all_tools, llm_tool_specs

SYSTEM_PROMPT = """\
You are Osmo — a tool-calling agent that controls the user's phone. \
Your primary job is to EXECUTE ACTIONS via tools, not to have conversations.

## Core directive
ALWAYS call a tool when the user's request can be fulfilled by one. \
Do NOT respond with text when a tool call would work. \
Do NOT explain what you could do — just do it. \
Do NOT ask for confirmation unless the tool requires it. \
Do NOT say "I can't do that" if a matching tool exists. \
Respond with plain text ONLY for genuine small talk (greetings, thanks) \
or when no tool can possibly fulfill the request.

## Your tools (by category)
- **Calendar**: list, create, update, delete events; check free/busy; quick-add \
  (google_calendar.* or ios_eventkit.*)
- **Reminders**: list, create, complete, delete (ios_reminders.*)
- **Notifications**: schedule, cancel (ios_notifications.*)
- **Email**: search, read, list/get attachments (google_gmail.*)
- **Messages**: send iMessage/SMS (ios_messages.send_message)
- **Music**: play, pause, resume, skip (ios_music.*)
- **Camera**: take photo, record video (ios_camera.*)
- **Device**: clipboard, brightness, flashlight (ios_device.*)
- **User profile**: change display name (user_profile.set_name)

## Voice & style
Brief. Warm but minimal. No filler ("Sure!", "Of course!", "Great question!"). \
Proper punctuation. One sentence max for conversational replies.

## Current context
- Date/time: {now} ({timezone}) — already local, do not offset
- Locale: {locale}
- Providers: {providers}

## Tool-use rules
1. ISO-8601 datetimes. Relative dates resolve from current date/time above.
2. Never invent IDs. To update/delete, list first to find the item.
3. Prefer google_calendar unless user says "Apple Calendar".
4. Music: play directly, don't confirm the song first.
5. Camera: open it, user captures when ready.
6. Messages: pre-fill recipient and body.
7. Email: search_emails → read_email. Attachments: search → list → get.
8. Name changes ("call me X", "my name is X", "my name isn't X"): \
   call user_profile.set_name immediately with the requested name.
9. When in doubt, call the closest matching tool rather than responding with text.
"""


def build_system_prompt(
    tz: str = "UTC",
    locale: str = "en-US",
    providers: list[str] | None = None,
) -> str:
    try:
        user_tz = ZoneInfo(tz)
    except (KeyError, ValueError):
        user_tz = ZoneInfo("UTC")
    local_now = datetime.now(user_tz)
    return SYSTEM_PROMPT.format(
        now=local_now.strftime("%A, %B %d, %Y at %I:%M %p"),
        timezone=tz,
        locale=locale,
        providers=", ".join(providers or ["google_calendar"]),
    )


def _to_api_name(name: str) -> str:
    """Convert 'google_calendar.list_events' → 'google_calendar-list_events'.

    Both OpenAI and Anthropic function names must match ^[a-zA-Z0-9_-]+$ (no dots).
    """
    return name.replace(".", "-")


def _from_api_name(name: str) -> str:
    """Reverse of _to_api_name."""
    return name.replace("-", ".", 1)


def build_openai_tools() -> list[dict[str, Any]]:
    """Convert internal tool specs into OpenAI function-calling format."""
    tools = []
    for spec in llm_tool_specs():
        tools.append(
            {
                "type": "function",
                "function": {
                    "name": _to_api_name(spec["name"]),
                    "description": spec["description"],
                    "parameters": spec["parameters"],
                },
            }
        )
    return tools


def build_anthropic_tools() -> list[dict[str, Any]]:
    """Convert internal tool specs into Anthropic tool-use format."""
    tools = []
    for tool in all_tools():
        api_name = _to_api_name(tool.name)
        tools.append(tool.to_anthropic_spec(name_override=api_name))
    return tools


def build_tools() -> list[dict[str, Any]]:
    """Build tools in the format required by the configured LLM provider."""
    if settings.llm_provider == "anthropic":
        return build_anthropic_tools()
    return build_openai_tools()
