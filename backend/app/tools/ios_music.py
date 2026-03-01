from __future__ import annotations

from typing import Any

from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _IOSTool(BaseTool):
    """Device-side tools — never executed on the server."""

    execution_target = "device"

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        raise RuntimeError(f"{self.name} is a device-side tool and cannot be executed server-side")


class IOSPlayMusicTool(_IOSTool):
    name = "ios_music.play"
    description = "Search Apple Music and play a song, album, or playlist. Requires Apple Music subscription."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search term — song name, artist, album, or genre"},
                "type": {
                    "type": "string",
                    "enum": ["song", "album", "playlist"],
                    "description": "What to search for (default song)",
                },
            },
            "required": ["query"],
        }


class IOSPauseMusicTool(_IOSTool):
    name = "ios_music.pause"
    description = "Pause the currently playing music."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {},
            "required": [],
        }


class IOSResumeMusicTool(_IOSTool):
    name = "ios_music.resume"
    description = "Resume playback of paused music."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {},
            "required": [],
        }


class IOSSkipMusicTool(_IOSTool):
    name = "ios_music.skip"
    description = "Skip to the next track."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "direction": {
                    "type": "string",
                    "enum": ["next", "previous"],
                    "description": "Skip forward or backward (default next)",
                },
            },
            "required": [],
        }


_TOOLS = [
    IOSPlayMusicTool(),
    IOSPauseMusicTool(),
    IOSResumeMusicTool(),
    IOSSkipMusicTool(),
]

for _t in _TOOLS:
    register_tool(_t)
