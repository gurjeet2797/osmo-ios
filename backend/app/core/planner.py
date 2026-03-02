from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.config import settings
from app.tools.registry import all_tools, get_skill_manifests, llm_tool_specs

_SYSTEM_PROMPT_TEMPLATE = """\
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
{tool_categories}

## Voice & style
Brief. Warm but minimal. No filler ("Sure!", "Of course!", "Great question!"). \
Proper punctuation. One sentence max for conversational replies.

## Current context
- Date/time: {now} ({timezone}) — already local, do not offset
- Locale: {locale}
- Providers: {providers}

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
) -> str:
    try:
        user_tz = ZoneInfo(tz)
    except (KeyError, ValueError):
        user_tz = ZoneInfo("UTC")
    local_now = datetime.now(user_tz)
    return _SYSTEM_PROMPT_TEMPLATE.format(
        tool_categories=_build_tool_categories(),
        tool_rules=_build_tool_rules(),
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
