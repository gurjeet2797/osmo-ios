from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSListRemindersTool(_IOSTool):
    name = "ios_reminders.list_reminders"
    description = "List reminders from the user's device, optionally filtered by list name or completion status."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "list_name": {"type": "string", "description": "Filter to a specific reminder list"},
                "include_completed": {"type": "boolean", "description": "Include completed reminders (default false)"},
            },
            "required": [],
        }


class IOSCreateReminderTool(_IOSTool):
    name = "ios_reminders.create_reminder"
    description = "Create a new reminder on the user's device with optional due date and priority."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "due_date": {"type": "string", "format": "date-time", "description": "ISO-8601 due date"},
                "priority": {"type": "integer", "description": "1=high, 5=medium, 9=low, 0=none"},
                "notes": {"type": "string"},
                "list_name": {"type": "string", "description": "Which reminder list to add to"},
            },
            "required": ["title"],
        }


class IOSCompleteReminderTool(_IOSTool):
    name = "ios_reminders.complete_reminder"
    description = "Mark a reminder as completed on the user's device."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "reminder_id": {"type": "string"},
            },
            "required": ["reminder_id"],
        }


class IOSDeleteReminderTool(_IOSTool):
    name = "ios_reminders.delete_reminder"
    description = "Delete a reminder from the user's device."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "reminder_id": {"type": "string"},
            },
            "required": ["reminder_id"],
        }


_TOOLS = [
    IOSListRemindersTool(),
    IOSCreateReminderTool(),
    IOSCompleteReminderTool(),
    IOSDeleteReminderTool(),
]

for _t in _TOOLS:
    register_tool(_t)
