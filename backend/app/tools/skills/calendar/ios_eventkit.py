from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools are never executed on the server.

    They exist so the LLM can reference them in ActionPlans.
    The executor serializes them as DeviceAction payloads for the iOS app.
    """

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSListEventsTool(_IOSTool):
    name = "ios_eventkit.list_events"
    description = "List events from Apple Calendar on the user's device in a date range."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "start": {"type": "string", "format": "date-time"},
                "end": {"type": "string", "format": "date-time"},
                "calendar_ids": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["start", "end"],
        }


class IOSCreateEventTool(_IOSTool):
    name = "ios_eventkit.create_event"
    description = "Create a new event in Apple Calendar on the user's device."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "start": {"type": "string", "format": "date-time"},
                "end": {"type": "string", "format": "date-time"},
                "calendar_id": {"type": "string"},
                "notes": {"type": "string"},
                "location": {"type": "string"},
                "alarms": {
                    "type": "array",
                    "items": {"type": "integer"},
                    "description": "Alarm offsets in minutes before the event (negative = before)",
                },
            },
            "required": ["title", "start", "end"],
        }


class IOSUpdateEventTool(_IOSTool):
    name = "ios_eventkit.update_event"
    description = "Update an existing event in Apple Calendar on the user's device."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "event_identifier": {"type": "string"},
                "patch_fields": {"type": "object"},
            },
            "required": ["event_identifier", "patch_fields"],
        }


class IOSDeleteEventTool(_IOSTool):
    name = "ios_eventkit.delete_event"
    description = "Delete an event from Apple Calendar on the user's device."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "event_identifier": {"type": "string"},
            },
            "required": ["event_identifier"],
        }


_TOOLS = [
    IOSListEventsTool(),
    IOSCreateEventTool(),
    IOSUpdateEventTool(),
    IOSDeleteEventTool(),
]

for _t in _TOOLS:
    register_tool(_t)
