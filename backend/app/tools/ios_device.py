from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSCopyToClipboardTool(_IOSTool):
    name = "ios_device.copy_to_clipboard"
    description = "Copy text or a URL to the user's clipboard."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to copy to clipboard"},
            },
            "required": ["text"],
        }


class IOSSetBrightnessTool(_IOSTool):
    name = "ios_device.set_brightness"
    description = "Set the device screen brightness. 0.0 is minimum, 1.0 is maximum."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "level": {"type": "number", "minimum": 0.0, "maximum": 1.0},
            },
            "required": ["level"],
        }


class IOSFlashlightTool(_IOSTool):
    name = "ios_device.flashlight"
    description = "Turn the device flashlight on or off, with optional brightness level."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "enabled": {"type": "boolean", "description": "true to turn on, false to turn off"},
                "level": {"type": "number", "minimum": 0.0, "maximum": 1.0, "description": "Brightness level (default 1.0)"},
            },
            "required": ["enabled"],
        }


_TOOLS = [
    IOSCopyToClipboardTool(),
    IOSSetBrightnessTool(),
    IOSFlashlightTool(),
]

for _t in _TOOLS:
    register_tool(_t)
