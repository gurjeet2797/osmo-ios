from __future__ import annotations

from datetime import datetime
from typing import Any

from app.connectors.google_calendar import GoogleCalendarClient
from app.schemas.command import VerificationResult
from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _GCalTool(BaseTool):
    execution_target = "server"

    def _client(self, ctx: ToolContext) -> GoogleCalendarClient:
        if ctx.google_credentials is None:
            raise RuntimeError("Google credentials not available")
        return GoogleCalendarClient(ctx.google_credentials)


class ListEventsTool(_GCalTool):
    name = "google_calendar.list_events"
    description = "List calendar events in a date range, optionally filtered by query text."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "time_min": {"type": "string", "format": "date-time"},
                "time_max": {"type": "string", "format": "date-time"},
                "query": {"type": "string"},
                "calendar_id": {"type": "string", "default": "primary"},
                "max_results": {"type": "integer", "default": 50},
            },
            "required": ["time_min", "time_max"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        events = client.list_events(
            time_min=datetime.fromisoformat(args["time_min"]),
            time_max=datetime.fromisoformat(args["time_max"]),
            query=args.get("query"),
            calendar_id=args.get("calendar_id", "primary"),
            max_results=args.get("max_results", 50),
        )
        return {"events": events, "count": len(events)}


class CreateEventTool(_GCalTool):
    name = "google_calendar.create_event"
    description = (
        "Create a new calendar event with title, start/end times, optional attendees and location."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "start": {"type": "string", "format": "date-time"},
                "end": {"type": "string", "format": "date-time"},
                "calendar_id": {"type": "string", "default": "primary"},
                "attendees": {"type": "array", "items": {"type": "string"}},
                "location": {"type": "string"},
                "description": {"type": "string"},
                "send_updates": {
                    "type": "string",
                    "enum": ["all", "externalOnly", "none"],
                    "default": "none",
                },
            },
            "required": ["title", "start", "end"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        event = client.create_event(
            title=args["title"],
            start=datetime.fromisoformat(args["start"]),
            end=datetime.fromisoformat(args["end"]),
            calendar_id=args.get("calendar_id", "primary"),
            attendees=args.get("attendees"),
            location=args.get("location"),
            description=args.get("description"),
            send_updates=args.get("send_updates", "none"),
        )
        return {"event_id": event["id"], "html_link": event.get("htmlLink"), "event": event}

    async def verify(
        self, args: dict[str, Any], result: dict[str, Any], context: ToolContext
    ) -> VerificationResult:
        client = self._client(context)
        event = client.get_event(result["event_id"], args.get("calendar_id", "primary"))
        discrepancies = []
        if event.get("summary") != args["title"]:
            discrepancies.append(
                f"title: expected '{args['title']}', got '{event.get('summary')}'"
            )
        return VerificationResult(matched=len(discrepancies) == 0, discrepancies=discrepancies)


class UpdateEventTool(_GCalTool):
    name = "google_calendar.update_event"
    description = "Update an existing calendar event by patching specific fields."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "event_id": {"type": "string"},
                "calendar_id": {"type": "string", "default": "primary"},
                "patch_fields": {"type": "object"},
                "send_updates": {
                    "type": "string",
                    "enum": ["all", "externalOnly", "none"],
                    "default": "none",
                },
            },
            "required": ["event_id", "patch_fields"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        event = client.update_event(
            event_id=args["event_id"],
            patch_fields=args["patch_fields"],
            calendar_id=args.get("calendar_id", "primary"),
            send_updates=args.get("send_updates", "none"),
        )
        return {"event_id": event["id"], "event": event}

    async def verify(
        self, args: dict[str, Any], result: dict[str, Any], context: ToolContext
    ) -> VerificationResult:
        client = self._client(context)
        event = client.get_event(result["event_id"], args.get("calendar_id", "primary"))
        discrepancies = []
        for key, value in args["patch_fields"].items():
            actual = event.get(key)
            if actual != value:
                discrepancies.append(f"{key}: expected {value!r}, got {actual!r}")
        return VerificationResult(matched=len(discrepancies) == 0, discrepancies=discrepancies)


class DeleteEventTool(_GCalTool):
    name = "google_calendar.delete_event"
    description = "Delete a calendar event by ID."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "event_id": {"type": "string"},
                "calendar_id": {"type": "string", "default": "primary"},
                "send_updates": {
                    "type": "string",
                    "enum": ["all", "externalOnly", "none"],
                    "default": "none",
                },
            },
            "required": ["event_id"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        client.delete_event(
            event_id=args["event_id"],
            calendar_id=args.get("calendar_id", "primary"),
            send_updates=args.get("send_updates", "none"),
        )
        return {"deleted": True, "event_id": args["event_id"]}


class FreeBusyTool(_GCalTool):
    name = "google_calendar.freebusy"
    description = "Query free/busy information for calendars in a time range to find open slots."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "time_min": {"type": "string", "format": "date-time"},
                "time_max": {"type": "string", "format": "date-time"},
                "calendar_ids": {
                    "type": "array",
                    "items": {"type": "string"},
                    "default": ["primary"],
                },
            },
            "required": ["time_min", "time_max"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        result = client.freebusy(
            time_min=datetime.fromisoformat(args["time_min"]),
            time_max=datetime.fromisoformat(args["time_max"]),
            calendar_ids=args.get("calendar_ids", ["primary"]),
        )
        return result


class QuickAddTool(_GCalTool):
    name = "google_calendar.quick_add"
    description = "Quickly create an event from a natural-language text string (Google parses it)."

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "calendar_id": {"type": "string", "default": "primary"},
            },
            "required": ["text"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        event = client.quick_add(
            text=args["text"],
            calendar_id=args.get("calendar_id", "primary"),
        )
        return {"event_id": event["id"], "html_link": event.get("htmlLink"), "event": event}


_TOOLS = [
    ListEventsTool(),
    CreateEventTool(),
    UpdateEventTool(),
    DeleteEventTool(),
    FreeBusyTool(),
    QuickAddTool(),
]

for _t in _TOOLS:
    register_tool(_t)
