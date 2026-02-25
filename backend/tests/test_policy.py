"""Tests for the policy gate."""

from app.core.policy import evaluate
from app.schemas.action_plan import RiskLevel


def test_destructive_action_requires_confirmation(destructive_plan):
    result = evaluate(destructive_plan)
    step = result.plan.steps[0]
    assert step.requires_confirmation is True
    assert step.risk_level == RiskLevel.high
    assert step.confirmation_phrase is not None


def test_attendee_action_requires_confirmation(attendee_plan):
    result = evaluate(attendee_plan)
    step = result.plan.steps[0]
    assert step.requires_confirmation is True
    assert step.risk_level == RiskLevel.medium


def test_safe_action_not_blocked(sample_plan):
    result = evaluate(sample_plan)
    assert not result.blocked
    step = result.plan.steps[0]
    assert step.requires_confirmation is False
    assert step.risk_level == RiskLevel.low


def test_risk_never_downgraded():
    """If LLM sets high risk, policy should not lower it."""
    from app.schemas.action_plan import ActionPlan, ActionStep

    plan = ActionPlan(
        user_intent="list events",
        steps=[
            ActionStep(
                tool_name="google_calendar.list_events",
                args={"time_min": "2025-01-01T00:00:00", "time_max": "2025-01-02T00:00:00"},
                risk_level=RiskLevel.high,
                execution_target="server",
            )
        ],
    )
    result = evaluate(plan)
    assert result.plan.steps[0].risk_level == RiskLevel.high


def test_send_updates_triggers_confirmation():
    from app.schemas.action_plan import ActionPlan, ActionStep

    plan = ActionPlan(
        user_intent="update event",
        steps=[
            ActionStep(
                tool_name="google_calendar.update_event",
                args={"event_id": "x", "patch_fields": {}, "send_updates": "all"},
                risk_level=RiskLevel.low,
                execution_target="server",
            )
        ],
    )
    result = evaluate(plan)
    step = result.plan.steps[0]
    assert step.requires_confirmation is True
    assert step.risk_level == RiskLevel.medium
