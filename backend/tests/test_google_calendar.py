"""Tests for Google Calendar tools (using mocked connector)."""

import pytest

import app.tools.skills.calendar.google_calendar  # noqa: F401 — register tools
import app.tools.skills.calendar.ios_eventkit  # noqa: F401 — register tools
from app.tools.base import ToolContext
from app.tools.registry import get_tool


def test_all_google_tools_registered():
    names = [
        "google_calendar.list_events",
        "google_calendar.create_event",
        "google_calendar.update_event",
        "google_calendar.delete_event",
        "google_calendar.freebusy",
        "google_calendar.quick_add",
    ]
    for name in names:
        tool = get_tool(name)
        assert tool is not None, f"Tool {name} not registered"
        assert tool.execution_target == "server"


def test_all_ios_tools_registered():
    names = [
        "ios_eventkit.list_events",
        "ios_eventkit.create_event",
        "ios_eventkit.update_event",
        "ios_eventkit.delete_event",
    ]
    for name in names:
        tool = get_tool(name)
        assert tool is not None, f"Tool {name} not registered"
        assert tool.execution_target == "device"


def test_tool_specs_have_required_fields():
    for name in ["google_calendar.create_event", "ios_eventkit.create_event"]:
        tool = get_tool(name)
        spec = tool.to_llm_spec()
        assert "name" in spec
        assert "description" in spec
        assert "parameters" in spec
        assert spec["parameters"]["type"] == "object"


@pytest.mark.asyncio
async def test_ios_tool_raises_on_server_execute():
    tool = get_tool("ios_eventkit.create_event")
    ctx = ToolContext(user_id="test")
    with pytest.raises(RuntimeError, match="device-side tool"):
        await tool.execute({"title": "x", "start": "2025-01-01", "end": "2025-01-01"}, ctx)


@pytest.mark.asyncio
async def test_google_list_events_calls_connector(monkeypatch):
    events_returned = [{"id": "e1", "summary": "Test"}]

    class FakeClient:
        def list_events(self, **kwargs):
            return events_returned

    import app.tools.skills.calendar.google_calendar as mod

    monkeypatch.setattr(mod, "GoogleCalendarClient", lambda creds: FakeClient())

    tool = get_tool("google_calendar.list_events")
    ctx = ToolContext(user_id="test", google_credentials="fake")
    result = await tool.execute(
        {"time_min": "2025-01-01T00:00:00", "time_max": "2025-01-02T00:00:00"},
        ctx,
    )
    assert result["count"] == 1
    assert result["events"] == events_returned


@pytest.mark.asyncio
async def test_google_create_event_calls_connector(monkeypatch):
    created = {"id": "new1", "htmlLink": "https://cal/new1", "summary": "Standup"}

    class FakeClient:
        def create_event(self, **kwargs):
            return created

    import app.tools.skills.calendar.google_calendar as mod

    monkeypatch.setattr(mod, "GoogleCalendarClient", lambda creds: FakeClient())

    tool = get_tool("google_calendar.create_event")
    ctx = ToolContext(user_id="test", google_credentials="fake")
    result = await tool.execute(
        {"title": "Standup", "start": "2025-01-01T09:00:00", "end": "2025-01-01T09:30:00"},
        ctx,
    )
    assert result["event_id"] == "new1"
