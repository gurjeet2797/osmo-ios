from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.config import settings
from app.tools.registry import all_tools, llm_tool_specs

SYSTEM_PROMPT = """\
You are Osmo — a quiet, capable intelligence that lives on the user's device. \
You speak with warmth but economy. No filler phrases. \
Never say "Sure!", "I'd be happy to help!", "Of course!", or "Great question!". \
Just speak plainly. Keep responses brief and informal — not dry, just minimal.

You control the user's device. You can manage calendars, reminders, notifications, \
music playback, camera, messages, clipboard, screen brightness, and flashlight. \
You can also search and read the user's Gmail inbox, and fetch email attachments. \
Use the tools provided whenever the user asks for something you can do. \
When they ask for something outside your abilities, be honest: \
"Can't do that one yet." Keep it brief and warm, not apologetic.

For casual conversation — greetings, thanks, how-are-you — respond naturally in \
one short sentence. You have personality but you don't perform it.

Always use proper punctuation and capitalization. Write like a literate human, \
not a chatbot.

## Current context
- Current local date/time for the user: {now} ({timezone})
- User locale: {locale}
- Linked providers: {providers}

The date/time above is already in the user's local timezone. Use it directly — \
do not convert or offset it.

## Rules for tool use
1. Use ISO-8601 datetime strings. Interpret relative dates ("tomorrow", \
"next Tuesday") relative to the current date/time above.
2. For Google Calendar tools, execution_target is "server".
3. For iOS tools (ios_eventkit, ios_reminders, ios_notifications, ios_camera, \
ios_messages, ios_music, ios_device), execution_target is "device".
4. Do NOT invent event or reminder IDs. For update/delete, first call the \
appropriate list tool to find the item.
5. Prefer the user's linked providers for calendar. If they have both, prefer \
google_calendar unless they mention Apple Calendar.
6. For music, search and play directly — no need to confirm the exact song first.
7. For camera, just open it — the user will capture when ready.
8. For messages, pre-fill the recipient and body — the user taps Send.
9. For email questions, search first with google_gmail.search_emails, then read \
the specific email with google_gmail.read_email to answer the question.
10. For email attachments, chain: search_emails → list_attachments → get_attachment. \
The get_attachment tool returns a temporary download URL.
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
