from __future__ import annotations

from typing import Any
from uuid import UUID

import structlog
from sqlalchemy import select

from app.models.user import User
from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool

log = structlog.get_logger()


class SetNameTool(BaseTool):
    name = "user_profile.set_name"
    description = "Update the user's display name. Use when the user says 'call me X' or 'my name is X'."

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        name = args.get("name", "").strip()
        if not name:
            return {"error": "Name cannot be empty"}

        db = context.db
        if db is None:
            return {"error": "Database session not available"}

        result = await db.execute(
            select(User).where(User.id == UUID(context.user_id))
        )
        user = result.scalar_one_or_none()
        if user is None:
            return {"error": "User not found"}

        user.name = name
        await db.commit()
        log.info("user_name_updated", user_id=context.user_id, name=name)
        return {"updated_name": name}

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "The new display name for the user.",
                },
            },
            "required": ["name"],
        }


_TOOLS = [SetNameTool()]
for _t in _TOOLS:
    register_tool(_t)
