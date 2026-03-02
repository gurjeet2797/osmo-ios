from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSTranslateTool(_IOSTool):
    name = "ios_translation.translate"
    description = "Translate text to another language using on-device translation."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "text": {
                    "type": "string",
                    "description": "Text to translate.",
                },
                "target_language": {
                    "type": "string",
                    "description": "Target language name (e.g. 'Spanish', 'French', 'Japanese', 'Chinese', 'Korean', 'German').",
                },
            },
            "required": ["text", "target_language"],
        }


_TOOLS = [
    IOSTranslateTool(),
]

for _t in _TOOLS:
    register_tool(_t)
