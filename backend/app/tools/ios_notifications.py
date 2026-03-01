from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSScheduleNotificationTool(_IOSTool):
    name = "ios_notifications.schedule"
    description = "Schedule a local notification on the user's device at a specific time."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "body": {"type": "string"},
                "fire_date": {"type": "string", "format": "date-time", "description": "ISO-8601 date-time to fire"},
                "identifier": {"type": "string", "description": "Unique ID for this notification (for cancellation)"},
            },
            "required": ["title", "body", "fire_date"],
        }


class IOSCancelNotificationTool(_IOSTool):
    name = "ios_notifications.cancel"
    description = "Cancel a previously scheduled local notification by identifier."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "identifier": {"type": "string"},
            },
            "required": ["identifier"],
        }


class IOSCancelAllNotificationsTool(_IOSTool):
    name = "ios_notifications.cancel_all"
    description = "Cancel all pending local notifications on the user's device."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {},
            "required": [],
        }


_TOOLS = [
    IOSScheduleNotificationTool(),
    IOSCancelNotificationTool(),
    IOSCancelAllNotificationsTool(),
]

for _t in _TOOLS:
    register_tool(_t)
