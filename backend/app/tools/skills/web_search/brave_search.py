from __future__ import annotations

from typing import Any

from app.connectors.brave_search import BraveSearchClient
from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class WebSearchTool(BaseTool):
    name = "web_search.search"
    description = "Search the web for current information, news, local businesses, weather, or any real-time data."
    execution_target = "server"

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query string.",
                },
                "count": {
                    "type": "integer",
                    "default": 5,
                    "minimum": 1,
                    "maximum": 20,
                    "description": "Number of results to return.",
                },
                "country": {
                    "type": "string",
                    "description": "Country code for localized results (e.g. 'US').",
                },
            },
            "required": ["query"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = BraveSearchClient()
        results = await client.search(
            query=args["query"],
            count=args.get("count", 5),
            country=args.get("country"),
        )
        return {"results": results, "count": len(results)}


_TOOLS = [
    WebSearchTool(),
]

for _t in _TOOLS:
    register_tool(_t)
