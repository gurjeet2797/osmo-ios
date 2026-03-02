from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from app.connectors.google_routes import GoogleRoutesClient
from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


def _resolve_origin(args: dict[str, Any], context: ToolContext) -> str:
    """Use explicit origin if provided, otherwise fall back to device location."""
    if "origin" in args and args["origin"]:
        return args["origin"]
    if context.latitude is not None and context.longitude is not None:
        return f"{context.latitude},{context.longitude}"
    raise ValueError("No origin provided and device location is not available")


class GetDirectionsTool(BaseTool):
    name = "google_routes.get_directions"
    description = "Get directions between two locations including duration, distance, and turn-by-turn steps."
    execution_target = "server"

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "origin": {
                    "type": "string",
                    "description": "Starting address or 'lat,lng'. Omit to use current device location.",
                },
                "destination": {
                    "type": "string",
                    "description": "Destination address or 'lat,lng'.",
                },
                "travel_mode": {
                    "type": "string",
                    "enum": ["DRIVE", "TRANSIT", "WALK", "BICYCLE"],
                    "default": "DRIVE",
                    "description": "Travel mode.",
                },
            },
            "required": ["destination"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        origin = _resolve_origin(args, context)
        client = GoogleRoutesClient()
        return await client.compute_route(
            origin=origin,
            destination=args["destination"],
            travel_mode=args.get("travel_mode", "DRIVE"),
        )


class GetDepartureTimeTool(BaseTool):
    name = "google_routes.get_departure_time"
    description = "Calculate when to leave to arrive at a destination by a specific time."
    execution_target = "server"

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "origin": {
                    "type": "string",
                    "description": "Starting address or 'lat,lng'. Omit to use current device location.",
                },
                "destination": {
                    "type": "string",
                    "description": "Destination address or 'lat,lng'.",
                },
                "arrival_time": {
                    "type": "string",
                    "description": "Desired arrival time in ISO-8601 format.",
                },
                "travel_mode": {
                    "type": "string",
                    "enum": ["DRIVE", "TRANSIT", "WALK", "BICYCLE"],
                    "default": "DRIVE",
                    "description": "Travel mode.",
                },
            },
            "required": ["destination", "arrival_time"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        origin = _resolve_origin(args, context)
        client = GoogleRoutesClient()

        # Compute route to get travel duration
        route = await client.compute_route(
            origin=origin,
            destination=args["destination"],
            travel_mode=args.get("travel_mode", "DRIVE"),
        )

        if "error" in route:
            return route

        duration_seconds = route["duration_seconds"]
        arrival_str = args["arrival_time"]

        # Parse arrival time
        try:
            arrival_dt = datetime.fromisoformat(arrival_str)
        except ValueError:
            return {"error": f"Invalid arrival_time format: {arrival_str}"}

        # If no timezone on arrival, assume user's timezone
        if arrival_dt.tzinfo is None:
            try:
                tz = ZoneInfo(context.timezone)
            except (KeyError, ValueError):
                tz = ZoneInfo("UTC")
            arrival_dt = arrival_dt.replace(tzinfo=tz)

        # Add a 5-minute buffer
        departure_dt = arrival_dt - timedelta(seconds=duration_seconds + 300)

        return {
            "departure_time": departure_dt.isoformat(),
            "arrival_time": arrival_dt.isoformat(),
            "travel_duration": route["duration_text"],
            "travel_duration_seconds": duration_seconds,
            "distance": route["distance_text"],
            "buffer_minutes": 5,
        }


class GetCommuteTimeTool(BaseTool):
    name = "google_routes.get_commute_time"
    description = "Get the current travel time between two locations, accounting for live traffic."
    execution_target = "server"

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "origin": {
                    "type": "string",
                    "description": "Starting address or 'lat,lng'. Omit to use current device location.",
                },
                "destination": {
                    "type": "string",
                    "description": "Destination address or 'lat,lng'.",
                },
                "travel_mode": {
                    "type": "string",
                    "enum": ["DRIVE", "TRANSIT", "WALK", "BICYCLE"],
                    "default": "DRIVE",
                    "description": "Travel mode.",
                },
            },
            "required": ["destination"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        origin = _resolve_origin(args, context)
        client = GoogleRoutesClient()
        route = await client.compute_route(
            origin=origin,
            destination=args["destination"],
            travel_mode=args.get("travel_mode", "DRIVE"),
            departure_time=datetime.now().astimezone().isoformat(),
        )
        # Return just the commute summary
        if "error" in route:
            return route
        return {
            "duration": route["duration_text"],
            "duration_seconds": route["duration_seconds"],
            "distance": route["distance_text"],
        }


_TOOLS = [
    GetDirectionsTool(),
    GetDepartureTimeTool(),
    GetCommuteTimeTool(),
]

for _t in _TOOLS:
    register_tool(_t)
