from __future__ import annotations

import structlog

from app.schemas.action_plan import ActionPlan, ActionStep, RiskLevel

log = structlog.get_logger()

DESTRUCTIVE_TOOLS = {
    "google_calendar.delete_event",
    "ios_eventkit.delete_event",
}

ATTENDEE_TOOLS = {
    "google_calendar.create_event",
    "google_calendar.update_event",
}

NOTIFICATION_SEND_VALUES = {"all", "externalOnly"}


class PolicyResult:
    def __init__(self, plan: ActionPlan, blocked: bool = False, block_reason: str | None = None):
        self.plan = plan
        self.blocked = blocked
        self.block_reason = block_reason


def evaluate(plan: ActionPlan) -> PolicyResult:
    """Apply hard policy rules to an ActionPlan.

    Mutates step-level risk_level and requires_confirmation where policy demands it.
    Never downgrades risk — only upgrades.
    """
    for step in plan.steps:
        _apply_step_policy(step)

    log.info(
        "policy.evaluated",
        plan_id=plan.plan_id,
        needs_confirmation=plan.needs_confirmation,
        max_risk=plan.max_risk,
    )
    return PolicyResult(plan=plan)


def _apply_step_policy(step: ActionStep) -> None:
    if step.tool_name in DESTRUCTIVE_TOOLS:
        _upgrade_risk(step, RiskLevel.high)
        step.requires_confirmation = True
        if not step.confirmation_phrase:
            step.confirmation_phrase = "This will permanently delete an event. Are you sure?"

    if step.tool_name in ATTENDEE_TOOLS:
        attendees = step.args.get("attendees", [])
        send_updates = step.args.get("send_updates", "none")

        if attendees:
            _upgrade_risk(step, RiskLevel.medium)
            step.requires_confirmation = True
            if not step.confirmation_phrase:
                names = ", ".join(attendees[:3])
                suffix = f" and {len(attendees) - 3} more" if len(attendees) > 3 else ""
                step.confirmation_phrase = f"This will invite {names}{suffix}. Confirm?"

        if send_updates in NOTIFICATION_SEND_VALUES:
            _upgrade_risk(step, RiskLevel.medium)
            step.requires_confirmation = True
            if not step.confirmation_phrase:
                step.confirmation_phrase = "This will send notifications to attendees. Confirm?"

    _check_missing_fields(step)


def _upgrade_risk(step: ActionStep, target: RiskLevel) -> None:
    order = {RiskLevel.low: 0, RiskLevel.medium: 1, RiskLevel.high: 2}
    if order[target] > order[step.risk_level]:
        step.risk_level = target


def _check_missing_fields(step: ActionStep) -> None:
    """Flag steps that are missing critical arguments for their tool."""
    required_by_tool = {
        "google_calendar.create_event": ["title", "start", "end"],
        "google_calendar.update_event": ["event_id", "patch_fields"],
        "google_calendar.delete_event": ["event_id"],
        "google_calendar.list_events": ["time_min", "time_max"],
        "ios_eventkit.create_event": ["title", "start", "end"],
        "ios_eventkit.update_event": ["event_identifier", "patch_fields"],
        "ios_eventkit.delete_event": ["event_identifier"],
        "ios_eventkit.list_events": ["start", "end"],
    }
    required = required_by_tool.get(step.tool_name, [])
    missing = [f for f in required if f not in step.args]
    if missing:
        log.warning(
            "policy.missing_fields",
            tool=step.tool_name,
            missing=missing,
        )
