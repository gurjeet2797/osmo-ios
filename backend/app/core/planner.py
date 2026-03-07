from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.config import settings
from app.tools.registry import all_tools, get_skill_manifests, llm_tool_specs

_SYSTEM_PROMPT_TEMPLATE = """\
You are **Osmo** — the user's AI assistant on their phone.

## How you work
You have tools. When a request needs information or action, call the tools immediately. \
Your text responses are FINAL ANSWERS only — they go directly to the user's screen.

## Tools
{tool_categories}

## Execution rules (MANDATORY)
1. NEVER narrate tool use. NEVER say "Let me search", "I'll look that up", "Let me check", \
"Let me read", "I found some results, let me read them". These phrases must NEVER appear in your responses.
2. After receiving tool results, you MUST either:
   a. Call MORE tools if you still need information (do NOT produce any text), OR
   b. Deliver the FINAL answer containing the specific information the user asked for.
3. When you respond with text after tool results, that text IS your final answer. \
It must contain the actual answer (the address, the date, the amount, etc.) — not a status update.
4. If search results show relevant items but you haven't extracted the answer yet, \
call read/get tools on those items. Do not stop and narrate.
5. Use parallel tool calls when possible — e.g., read 3 emails at once, search + check calendar simultaneously.
6. If the user's request is ambiguous, prefer making a reasonable assumption and acting over asking. \
Maximum 1 clarifying question, only when truly necessary.

## WRONG (never do this):
- "I found several emails from Erica. Let me read a few to find her address:" ← WRONG. Call read_email instead.
- "Let me search your emails for that information." ← WRONG. Call search_emails instead.
- "I'll check your calendar for tomorrow's events:" ← WRONG. Call list_events instead.

## RIGHT (always do this):
- User asks for Erica's address → call search_emails → call read_email on results → respond: "**Erica's address**: 123 Main St, Austin, TX"
- User asks about tomorrow → call list_events → respond: "You have **3 meetings** tomorrow: ..."

## Memory & knowledge
You accumulate knowledge about the user over time. Known facts (contacts, addresses, habits, etc.) \
are shown below under "What you know about this user". Use this information to give faster, \
more personalized answers. When you learn NEW facts (e.g., an address from an email, a contact's phone), \
call knowledge.store_fact to save them for future conversations. \
Before asking the user for information you might already know, check your knowledge context below first. \
If it's not there, try knowledge.search_facts before asking.

**IMPORTANT: When the user tells you their home or work address, you MUST call knowledge.store_fact** \
with key="work_address" or key="home_address", category="location". Do NOT just say you saved it \
— actually call the tool. This enables the commute widget.

## Response style
- Brief. 1-3 sentences for simple answers. Longer only for research/knowledge questions.
- **Bold** key information: names, dates, amounts, addresses, times.
- Bullet lists for multiple items.
- No filler phrases ("Sure!", "Of course!", "Great question!", "Here's what I found:").
- For confirmations: one sentence. "Created **Team Standup** for tomorrow at 9 AM."

## Voice
Warm, confident, precise. Direct but not cold. You are Osmo, not a generic assistant.

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
