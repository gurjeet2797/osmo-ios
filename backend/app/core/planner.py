from __future__ import annotations

import json
from datetime import UTC, datetime

import structlog
from pydantic import ValidationError

from app.connectors.llm import LLMClient
from app.schemas.action_plan import ActionPlan
from app.tools.registry import llm_tool_specs

log = structlog.get_logger()

SYSTEM_PROMPT_TEMPLATE = """\
You are the planning engine for Osmo, a voice-driven calendar assistant.

Your job: given a user's spoken command, produce a structured ActionPlan JSON that \
describes exactly what tool calls to make.

## Current context
- Current date/time: {now}
- User timezone: {timezone}
- User locale: {locale}
- Linked providers: {providers}

## Available tools
{tool_specs}

## Output format
Return a JSON object with this exact structure:
{{
  "user_intent": "<short summary of what the user wants>",
  "steps": [
    {{
      "tool_name": "<one of the tool names above>",
      "args": {{ ... tool-specific arguments ... }},
      "risk_level": "low" | "medium" | "high",
      "requires_confirmation": true | false,
      "confirmation_phrase": "<what to say to the user for confirmation, or null>",
      "execution_target": "server" | "device"
    }}
  ]
}}

## Rules
1. Use iso-8601 datetime strings for all dates/times. Interpret relative dates \
(\"tomorrow\", \"next Tuesday\") relative to the current date/time above.
2. For Google Calendar tools, set execution_target to "server".
3. For iOS EventKit tools, set execution_target to "device".
4. Set requires_confirmation=true for: deletes, cancellations, inviting attendees, \
or any action that sends notifications to others.
5. Set risk_level="high" for deletes/cancellations, "medium" for updates or attendee \
actions, "low" for reads and simple creates.
6. If the command is ambiguous or missing critical info (no date, no title), return:
   {{"user_intent": "<what you understood>", "clarification_needed": "<question>", "steps": []}}
7. If the user wants to see their schedule, use list_events.
8. If the user wants to find free time, use freebusy.
9. Prefer the user's linked providers. If they have both google_calendar and \
ios_eventkit, prefer google_calendar unless they explicitly mention Apple Calendar.
10. Do NOT invent event IDs. For update/delete operations on events the user \
references by name/time, first add a list_events step to find the event, then \
reference its ID in subsequent steps.

## Few-shot examples

User: "What's on my calendar tomorrow?"
{{
  "user_intent": "List tomorrow's events",
  "steps": [
    {{
      "tool_name": "google_calendar.list_events",
      "args": {{
        "time_min": "{tomorrow_start}",
        "time_max": "{tomorrow_end}"
      }},
      "risk_level": "low",
      "requires_confirmation": false,
      "confirmation_phrase": null,
      "execution_target": "server"
    }}
  ]
}}

User: "Schedule a meeting with John next Tuesday at 2pm for 1 hour"
{{
  "user_intent": "Create a 1-hour meeting with John next Tuesday at 2pm",
  "steps": [
    {{
      "tool_name": "google_calendar.create_event",
      "args": {{
        "title": "Meeting with John",
        "start": "{next_tuesday_2pm}",
        "end": "{next_tuesday_3pm}",
        "attendees": ["john"]
      }},
      "risk_level": "medium",
      "requires_confirmation": true,
      "confirmation_phrase": "I'll create a 1-hour meeting with John next Tuesday 2-3pm. Confirm?",
      "execution_target": "server"
    }}
  ]
}}

User: "Cancel my dentist appointment"
{{
  "user_intent": "Delete the dentist appointment",
  "steps": [
    {{
      "tool_name": "google_calendar.list_events",
      "args": {{
        "time_min": "{now_iso}",
        "time_max": "{two_weeks_out}",
        "query": "dentist"
      }},
      "risk_level": "low",
      "requires_confirmation": false,
      "confirmation_phrase": null,
      "execution_target": "server"
    }}
  ],
  "pending_delete": true
}}
"""


def _build_system_prompt(tz: str, locale: str, providers: list[str]) -> str:
    now = datetime.now(UTC)
    specs = json.dumps(llm_tool_specs(), indent=2)

    from datetime import timedelta

    tomorrow_start = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    tomorrow_end = tomorrow_start + timedelta(days=1)

    days_until_tuesday = (1 - now.weekday()) % 7 or 7
    next_tuesday = now + timedelta(days=days_until_tuesday)
    next_tuesday_2pm = next_tuesday.replace(hour=14, minute=0, second=0, microsecond=0)
    next_tuesday_3pm = next_tuesday_2pm + timedelta(hours=1)

    return SYSTEM_PROMPT_TEMPLATE.format(
        now=now.isoformat(),
        timezone=tz,
        locale=locale,
        providers=", ".join(providers),
        tool_specs=specs,
        tomorrow_start=tomorrow_start.isoformat(),
        tomorrow_end=tomorrow_end.isoformat(),
        next_tuesday_2pm=next_tuesday_2pm.isoformat(),
        next_tuesday_3pm=next_tuesday_3pm.isoformat(),
        now_iso=now.isoformat(),
        two_weeks_out=(now + timedelta(weeks=2)).isoformat(),
    )


class Planner:
    def __init__(self, llm: LLMClient):
        self._llm = llm

    async def plan(
        self,
        transcript: str,
        timezone: str = "UTC",
        locale: str = "en-US",
        linked_providers: list[str] | None = None,
    ) -> ActionPlan | dict:
        """Produce an ActionPlan from a user transcript.

        Returns an ActionPlan on success, or a dict with clarification_needed on ambiguity.
        """
        providers = linked_providers or ["google_calendar"]
        system_prompt = _build_system_prompt(timezone, locale, providers)
        specs = llm_tool_specs()

        raw = await self._llm.plan(system_prompt, transcript, specs)

        if raw.get("clarification_needed"):
            log.info("planner.clarification_needed", question=raw["clarification_needed"])
            return raw

        try:
            plan = ActionPlan(
                user_intent=raw.get("user_intent", transcript),
                timezone=timezone,
                locale=locale,
                steps=raw.get("steps", []),
            )
        except ValidationError as exc:
            log.warning("planner.validation_failed", error=str(exc))
            raw_retry = await self._llm.plan_with_retry(
                system_prompt, transcript, specs, validation_error=str(exc)
            )
            if raw_retry.get("clarification_needed"):
                return raw_retry
            plan = ActionPlan(
                user_intent=raw_retry.get("user_intent", transcript),
                timezone=timezone,
                locale=locale,
                steps=raw_retry.get("steps", []),
            )

        log.info(
            "planner.plan_created",
            plan_id=plan.plan_id,
            steps=len(plan.steps),
            intent=plan.user_intent,
        )
        return plan
