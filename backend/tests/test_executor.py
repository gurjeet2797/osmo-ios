"""Tests for the executor router."""

import pytest

from app.core.executor import Executor


@pytest.mark.asyncio
async def test_server_tool_execution(sample_plan, tool_context, monkeypatch):
    """Server tool should be dispatched to the registered tool's execute()."""
    called_with = {}

    async def fake_execute(self, args, context):
        called_with.update(args)
        return {"event_id": "new123", "html_link": "https://cal/new123", "event": {}}

    import app.tools.google_calendar as gcal_tools

    monkeypatch.setattr(gcal_tools.CreateEventTool, "execute", fake_execute)

    executor = Executor()
    result = await executor.execute_plan(sample_plan, tool_context)

    assert result.all_succeeded
    assert len(result.step_results) == 1
    assert called_with["title"] == "Team standup"


@pytest.mark.asyncio
async def test_device_tool_returns_device_action(device_plan, tool_context):
    """Device-side tool should not execute, but produce a DeviceAction."""
    executor = Executor()
    result = await executor.execute_plan(device_plan, tool_context)

    assert result.all_succeeded
    assert len(result.device_actions) == 1
    da = result.device_actions[0]
    assert da.tool_name == "ios_eventkit.create_event"
    assert da.args["title"] == "Dentist"


@pytest.mark.asyncio
async def test_idempotency_skips_duplicate(sample_plan, tool_context, monkeypatch):
    call_count = 0

    async def fake_execute(self, args, context):
        nonlocal call_count
        call_count += 1
        return {"event_id": "e1"}

    import app.tools.google_calendar as gcal_tools

    monkeypatch.setattr(gcal_tools.CreateEventTool, "execute", fake_execute)

    key = sample_plan.steps[0].idempotency_key
    executor = Executor(executed_keys={key})
    result = await executor.execute_plan(sample_plan, tool_context)

    assert result.all_succeeded
    assert call_count == 0


@pytest.mark.asyncio
async def test_confirmation_steps_skipped(tool_context):
    from app.schemas.action_plan import ActionPlan, ActionStep

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
    executor = Executor()
    result = await executor.execute_plan(plan, tool_context)
    assert len(result.step_results) == 0


@pytest.mark.asyncio
async def test_execute_confirmed_runs_all(tool_context, monkeypatch):
    from app.schemas.action_plan import ActionPlan, ActionStep

    async def fake_delete(self, args, context):
        return {"deleted": True}

    import app.tools.google_calendar as gcal_tools

    monkeypatch.setattr(gcal_tools.DeleteEventTool, "execute", fake_delete)

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
    executor = Executor()
    result = await executor.execute_confirmed_plan(plan, tool_context)
    assert result.all_succeeded
    assert len(result.step_results) == 1
