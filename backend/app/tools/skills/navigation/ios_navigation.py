from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSOpenInMapsTool(_IOSTool):
    name = "ios_navigation.open_in_maps"
    description = "Open Apple Maps with directions to a destination."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "destination": {
                    "type": "string",
                    "description": "Destination address or place name.",
                },
                "travel_mode": {
                    "type": "string",
                    "enum": ["driving", "transit", "walking"],
                    "default": "driving",
                    "description": "Travel mode for directions.",
                },
            },
            "required": ["destination"],
        }


_TOOLS = [
    IOSOpenInMapsTool(),
]

for _t in _TOOLS:
    register_tool(_t)
