from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSTakePhotoTool(_IOSTool):
    name = "ios_camera.take_photo"
    description = "Open the camera on the user's device to take a photo. The photo is saved to their photo library."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "camera": {
                    "type": "string",
                    "enum": ["front", "back"],
                    "description": "Which camera to use (default back)",
                },
            },
            "required": [],
        }


class IOSRecordVideoTool(_IOSTool):
    name = "ios_camera.record_video"
    description = "Open the camera on the user's device to record a video. The video is saved to their photo library."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "camera": {
                    "type": "string",
                    "enum": ["front", "back"],
                    "description": "Which camera to use (default back)",
                },
                "max_duration": {
                    "type": "number",
                    "description": "Maximum recording duration in seconds",
                },
            },
            "required": [],
        }


_TOOLS = [
    IOSTakePhotoTool(),
    IOSRecordVideoTool(),
]

for _t in _TOOLS:
    register_tool(_t)
