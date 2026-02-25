import uuid

import pytest

from app.schemas.action_plan import ActionPlan, ActionStep, RiskLevel
from app.tools.base import ToolContext


@pytest.fixture
def tool_context():
    return ToolContext(user_id=str(uuid.uuid4()), timezone="America/New_York")


@pytest.fixture
def sample_plan():
    return ActionPlan(
        user_intent="Create a meeting tomorrow at 2pm",
        timezone="America/New_York",
        locale="en-US",
        steps=[
            ActionStep(
                tool_name="google_calendar.create_event",
                args={
                    "title": "Team standup",
                    "start": "2025-03-01T14:00:00",
                    "end": "2025-03-01T15:00:00",
                },
                risk_level=RiskLevel.low,
                requires_confirmation=False,
                execution_target="server",
            )
        ],
    )


@pytest.fixture
def destructive_plan():
    return ActionPlan(
        user_intent="Delete my dentist appointment",
        timezone="UTC",
        steps=[
            ActionStep(
                tool_name="google_calendar.delete_event",
                args={"event_id": "abc123"},
                risk_level=RiskLevel.low,
                requires_confirmation=False,
                execution_target="server",
            )
        ],
    )


@pytest.fixture
def device_plan():
    return ActionPlan(
        user_intent="Create event on Apple Calendar",
        timezone="UTC",
        steps=[
            ActionStep(
                tool_name="ios_eventkit.create_event",
                args={
                    "title": "Dentist",
                    "start": "2025-03-01T10:00:00",
                    "end": "2025-03-01T11:00:00",
                },
                risk_level=RiskLevel.low,
                requires_confirmation=False,
                execution_target="device",
            )
        ],
    )


@pytest.fixture
def attendee_plan():
    return ActionPlan(
        user_intent="Schedule meeting with John",
        timezone="UTC",
        steps=[
            ActionStep(
                tool_name="google_calendar.create_event",
                args={
                    "title": "Meeting with John",
                    "start": "2025-03-01T14:00:00",
                    "end": "2025-03-01T15:00:00",
                    "attendees": ["john@example.com"],
                    "send_updates": "all",
                },
                risk_level=RiskLevel.low,
                requires_confirmation=False,
                execution_target="server",
            )
        ],
    )
