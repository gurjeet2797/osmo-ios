from __future__ import annotations

import json
from typing import Any

import structlog
from sqlalchemy import select

from app.models.user_preference import UserPreference
from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool

log = structlog.get_logger()


class SetPreferenceTool(BaseTool):
    name = "memory.set_preference"
    description = (
        "Store a user preference or habit. Use when the user says 'I prefer...', "
        "'always use...', 'default to...', or similar. Never store sensitive data."
    )

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        key = args.get("key", "").strip()
        value = args.get("value", "").strip()
        if not key or not value:
            return {"error": "Both key and value are required"}

        db = context.db
        if db is None:
            return {"error": "Database session not available"}

        result = await db.execute(
            select(UserPreference).where(
                UserPreference.user_id == context.user_id,
                UserPreference.key == key,
            )
        )
        pref = result.scalar_one_or_none()

        if pref is None:
            pref = UserPreference(
                user_id=context.user_id,
                key=key,
                value=value,
                source="explicit",
                confidence=1.0,
            )
            db.add(pref)
        else:
            pref.value = value
            pref.source = "explicit"
            pref.confidence = 1.0

        await db.commit()
        log.info("preference.stored", user_id=context.user_id, key=key)
        return {"stored": True, "key": key, "value": value}

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "key": {
                    "type": "string",
                    "description": (
                        "Short descriptive key, e.g. 'preferred_calendar', "
                        "'default_meeting_duration', 'morning_routine'."
                    ),
                },
                "value": {
                    "type": "string",
                    "description": "The preference value as a string (can be JSON for complex values).",
                },
            },
            "required": ["key", "value"],
        }


class GetPreferencesTool(BaseTool):
    name = "memory.get_preferences"
    description = "Retrieve all stored user preferences and habits."

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        db = context.db
        if db is None:
            return {"error": "Database session not available"}

        result = await db.execute(
            select(UserPreference)
            .where(UserPreference.user_id == context.user_id)
            .order_by(UserPreference.key)
        )
        prefs = result.scalars().all()

        if not prefs:
            return {"preferences": {}, "message": "No preferences stored yet."}

        return {
            "preferences": {p.key: p.value for p in prefs},
            "count": len(prefs),
        }

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {},
        }


_TOOLS = [SetPreferenceTool(), GetPreferencesTool()]
for _t in _TOOLS:
    register_tool(_t)
