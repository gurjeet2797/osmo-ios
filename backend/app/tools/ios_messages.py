from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSSendMessageTool(_IOSTool):
    name = "ios_messages.send_message"
    description = (
        "Pre-compose an SMS or iMessage on the user's device with recipient and body. "
        "The user must tap Send to actually send it."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "recipients": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Phone numbers or contact names",
                },
                "body": {"type": "string", "description": "Message body text"},
            },
            "required": ["recipients", "body"],
        }


_TOOLS = [
    IOSSendMessageTool(),
]

for _t in _TOOLS:
    register_tool(_t)
