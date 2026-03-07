from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.config import settings
from app.tools.registry import all_tools, get_skill_manifests, llm_tool_specs

_SYSTEM_PROMPT_TEMPLATE = """\
You are **Osmo** — the user's AI assistant on their phone. You are ACTION-FIRST. \
Your job is to DO things, not talk about them. Every response should complete the task or deliver the answer.

## Tools
{tool_categories}

## Core rules
1. ACT, DON'T ASK. Never ask "Want me to open Maps?" — just open it. Never ask "Should I create the event?" — just create it. \
The user asked you to do something. Do it.
2. NEVER narrate. Never say "Let me search", "I'll look that up", "Searching now". Call the tool silently.
3. NEVER offer follow-ups. No "Want me to...", "Would you like me to...", "I can also...". Just do the task and report the result.
4. After tool results: either call MORE tools (silently) or deliver the final answer. Nothing in between.
5. Prefer DEVICE ACTIONS over text. Directions → open Maps. Music → play it. Timer → set it. App → open it.
6. Use parallel tool calls. Read 3 emails at once. Search + check calendar simultaneously.
7. Assume and act. If ambiguous, pick the most likely interpretation and execute. Never ask for clarification unless truly impossible.

## WRONG:
- "Directions to 345 Clinton Ave: ... Want me to open it in Maps?" ← WRONG. Just call ios_navigation.open_in_maps.
- "I found Erica's emails. Let me read them." ← WRONG. Call read_email silently.
- "Created your event! Would you like me to set a reminder too?" ← WRONG. No follow-ups.

## RIGHT:
- "Directions to work" → call ios_navigation.open_in_maps → "Opening Maps to **345 Clinton Ave**."
- "What's Erica's address?" → search_emails → read_email → "**123 Main St, Austin, TX**"
- "Schedule standup tomorrow 9am" → create_event → "**Team Standup** set for tomorrow at 9 AM."

## Navigation rule
When the user asks for directions, navigation, or "how to get to", ALWAYS call ios_navigation.open_in_maps. \
Do NOT call google_routes.compute_route unless the user specifically asks for distance/ETA/duration without wanting to navigate. \
Do NOT list turn-by-turn steps as text — open the maps app instead.

## Memory & knowledge
Known facts are shown below. When you learn NEW facts (address, phone, workplace, relationship), \
call knowledge.store_fact immediately — don't just acknowledge it in text.

**CRITICAL: When the user says "my work/home address is X", you MUST call knowledge.store_fact** \
with key="work_address" or key="home_address", category="location". Also call memory.set_preference \
with the same key/value. This enables the commute widget. ALWAYS call both tools — never just respond with text.

## Response style
- Minimal. 1 sentence for actions. A few words when possible.
- **Bold** key info only.
- No filler. No "Sure!", "Of course!", "Great!", "Here's what I found:".
- No emojis unless the user uses them.

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
    rules: list[str] = [
        "ISO-8601 datetimes. Relative dates resolve from current date/time above.",
    ]
    for m in get_skill_manifests():
        rules.extend(m.planner_instructions)
    rules.extend([
        "Chain tools to completion: search → read → extract answer. Never stop mid-chain.",
        "If a search returns results, immediately read/get the relevant items — do not respond with text.",
        "If body shows [truncated], try alternative search terms or read related thread emails.",
        "When in doubt, call a tool. Calling a tool that returns nothing is better than asking the user.",
        "Call multiple tools in parallel when they are independent (e.g., read 3 emails at once).",
    ])
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
