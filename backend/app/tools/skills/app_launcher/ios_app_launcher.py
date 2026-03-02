from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSOpenAppTool(_IOSTool):
    name = "ios_app_launcher.open_app"
    description = "Open an app on the user's iPhone by name."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "app_name": {
                    "type": "string",
                    "description": "Name of the app to open (e.g. 'Maps', 'Settings', 'Safari', 'Photos').",
                },
            },
            "required": ["app_name"],
        }


_TOOLS = [
    IOSOpenAppTool(),
]

for _t in _TOOLS:
    register_tool(_t)
