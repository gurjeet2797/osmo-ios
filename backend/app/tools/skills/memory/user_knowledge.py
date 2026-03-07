from __future__ import annotations

from typing import Any

from app.core.knowledge import KnowledgeManager
from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class StoreFactTool(BaseTool):
    name = "knowledge.store_fact"
    description = (
        "Store a fact about the user or their contacts for future reference. "
        "Use when you learn something worth remembering: a contact's address, "
        "the user's workplace, a recurring pattern, etc."
    )

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        db = context.db
        if db is None:
            return {"error": "Database session not available"}

        km = KnowledgeManager(db, context.user_id)
        is_new = await km.store(
            key=args["key"],
            value=args["value"],
            category=args.get("category", "general"),
            source="explicit",
            confidence=1.0,
        )
        return {"stored": True, "is_new": is_new, "key": args["key"]}

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "key": {
                    "type": "string",
                    "description": (
                        "Structured key like 'contact:erica_humphrey:address', "
                        "'personal:workplace', 'habit:preferred_meeting_time'."
                    ),
                },
                "value": {
                    "type": "string",
                    "description": "The fact value, e.g. '123 Main St, Austin, TX 78701'.",
                },
                "category": {
                    "type": "string",
                    "enum": ["contact", "location", "personal", "work", "habit", "general"],
                    "description": "Fact category for organization.",
                },
            },
            "required": ["key", "value", "category"],
        }


class SearchFactsTool(BaseTool):
    name = "knowledge.search_facts"
    description = (
        "Search the user's stored knowledge base for facts about contacts, "
        "locations, habits, or personal details. Use before asking the user "
        "for information you might already know."
    )

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        db = context.db
        if db is None:
            return {"error": "Database session not available"}

        km = KnowledgeManager(db, context.user_id)
        facts = await km.search(
            query=args["query"],
            category=args.get("category"),
            limit=args.get("limit", 20),
        )
        return {"facts": facts, "count": len(facts)}

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search keyword (matches against fact keys and values).",
                },
                "category": {
                    "type": "string",
                    "enum": ["contact", "location", "personal", "work", "habit", "general"],
                    "description": "Optional: filter by category.",
                },
                "limit": {
                    "type": "integer",
                    "default": 20,
                    "description": "Max results to return.",
                },
            },
            "required": ["query"],
        }


_TOOLS = [StoreFactTool(), SearchFactsTool()]
for _t in _TOOLS:
    register_tool(_t)
