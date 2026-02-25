"""Tests for ActionPlan schema validation and planner output parsing."""

import pytest

from app.schemas.action_plan import ActionPlan, ActionStep, RiskLevel


def test_action_plan_defaults():
    plan = ActionPlan(user_intent="test")
    assert plan.plan_id
    assert plan.timezone == "UTC"
    assert plan.locale == "en-US"
    assert plan.steps == []
    assert plan.created_at is not None


def test_action_plan_needs_confirmation_false(sample_plan):
    assert not sample_plan.needs_confirmation


def test_action_plan_needs_confirmation_true():
    plan = ActionPlan(
        user_intent="delete event",
        steps=[
            ActionStep(
                tool_name="google_calendar.delete_event",
                args={"event_id": "x"},
                requires_confirmation=True,
                execution_target="server",
            )
        ],
    )
    assert plan.needs_confirmation


def test_action_plan_max_risk():
    plan = ActionPlan(
        user_intent="mixed risk",
        steps=[
            ActionStep(
                tool_name="google_calendar.list_events",
                args={"time_min": "2025-01-01T00:00:00", "time_max": "2025-01-02T00:00:00"},
                risk_level=RiskLevel.low,
                execution_target="server",
            ),
            ActionStep(
                tool_name="google_calendar.delete_event",
                args={"event_id": "x"},
                risk_level=RiskLevel.high,
                execution_target="server",
            ),
        ],
    )
    assert plan.max_risk == RiskLevel.high


def test_action_step_idempotency_key():
    step1 = ActionStep(tool_name="t", args={}, execution_target="server")
    step2 = ActionStep(tool_name="t", args={}, execution_target="server")
    assert step1.idempotency_key != step2.idempotency_key


def test_action_plan_from_llm_dict():
    """Simulate parsing raw LLM output into ActionPlan."""
    raw = {
        "user_intent": "List tomorrow's events",
        "steps": [
            {
                "tool_name": "google_calendar.list_events",
                "args": {
                    "time_min": "2025-03-01T00:00:00",
                    "time_max": "2025-03-02T00:00:00",
                },
                "risk_level": "low",
                "requires_confirmation": False,
                "confirmation_phrase": None,
                "execution_target": "server",
            }
        ],
    }
    plan = ActionPlan(**raw)
    assert len(plan.steps) == 1
    assert plan.steps[0].tool_name == "google_calendar.list_events"
    assert plan.max_risk == RiskLevel.low


def test_action_plan_rejects_invalid_risk():
    with pytest.raises(Exception):
        ActionStep(
            tool_name="t",
            args={},
            risk_level="catastrophic",  # type: ignore[arg-type]
            execution_target="server",
        )
