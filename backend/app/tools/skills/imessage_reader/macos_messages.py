from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _MacOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class MacOSSearchConversationsTool(_MacOSTool):
    name = "macos_messages.search_conversations"
    description = (
        "Search iMessage conversations by contact name or phone number on macOS. "
        "Returns matching chat identifiers and display names."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Contact name, phone number, or email to search for",
                },
            },
            "required": ["query"],
        }


class MacOSReadThreadTool(_MacOSTool):
    name = "macos_messages.read_thread"
    description = (
        "Read messages from a specific iMessage thread on macOS. "
        "Requires the chat_guid from search_conversations."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "chat_guid": {
                    "type": "string",
                    "description": "Chat GUID (e.g. 'iMessage;-;+1234567890')",
                },
                "limit": {
                    "type": "integer",
                    "description": "Max messages to return (default 50)",
                    "default": 50,
                },
            },
            "required": ["chat_guid"],
        }


class MacOSGetRecentTool(_MacOSTool):
    name = "macos_messages.get_recent"
    description = (
        "Get recent iMessage messages across all conversations on macOS."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "limit": {
                    "type": "integer",
                    "description": "Max messages to return (default 20)",
                    "default": 20,
                },
            },
            "required": [],
        }


_TOOLS = [
    MacOSSearchConversationsTool(),
    MacOSReadThreadTool(),
    MacOSGetRecentTool(),
]

for _t in _TOOLS:
    register_tool(_t)
