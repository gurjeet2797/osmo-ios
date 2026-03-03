from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.config import settings
from app.tools.registry import all_tools, get_skill_manifests, llm_tool_specs

_SYSTEM_PROMPT_TEMPLATE = """\
You are Osmo — a tool-calling agent that controls the user's phone. \
EXECUTE ACTIONS via tools. Do NOT explain — just do it.

## Core directive
ALWAYS call a tool when possible. Text-only for small talk or when no tool fits. \
When the user's request is ambiguous, ask a clarifying question. Be specific about what you need.

## Tools
{tool_categories}

## Voice & style
Brief, warm, minimal. No filler. 1-2 sentences max. Use **bold** and bullets for scannability. \
If the user asks about something physical and no photo is attached, suggest: "Want to snap a photo? I can help more with a picture."

## Context
{now} ({timezone}) · {locale} · {providers} · Location: {location}

## Tool-use rules
{tool_rules}
"""


def _build_tool_categories() -> str:
    manifests = get_skill_manifests()
    if not manifests:
        return "- (no skills loaded)"
    return "\n".join(
        f"- **{m.display_name}**: {m.description}" for m in manifests
    )


def _build_tool_rules() -> str:
    rules: list[str] = ["ISO-8601 datetimes. Relative dates resolve from current date/time above."]
    for m in get_skill_manifests():
        rules.extend(m.planner_instructions)
    rules.append("When in doubt, call the closest matching tool rather than responding with text.")
    return "\n".join(f"{i}. {rule}" for i, rule in enumerate(rules, start=1))


def build_system_prompt(
    tz: str = "UTC",
    locale: str = "en-US",
    providers: list[str] | None = None,
    latitude: float | None = None,
    longitude: float | None = None,
    user_preferences: str = "",
) -> str:
    try:
        user_tz = ZoneInfo(tz)
    except (KeyError, ValueError):
        user_tz = ZoneInfo("UTC")
    local_now = datetime.now(user_tz)

    if latitude is not None and longitude is not None:
        location_str = f"{latitude:.4f}, {longitude:.4f}"
    else:
        location_str = "not available"

    prompt = _SYSTEM_PROMPT_TEMPLATE.format(
        tool_categories=_build_tool_categories(),
        tool_rules=_build_tool_rules(),
        now=local_now.strftime("%a %b %-d %Y %-I:%M %p"),
        timezone=tz,
        locale=locale,
        providers=", ".join(providers or ["google_calendar"]),
        location=location_str,
    )

    if user_preferences:
        prompt += "\n\n" + user_preferences

    return prompt


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
