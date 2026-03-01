from __future__ import annotations

from typing import Any

from app.api.attachments import store_attachment
from app.connectors.google_gmail import GoogleGmailClient
from app.tools.base import BaseTool, ToolContext
from app.tools.registry import register_tool


class _GmailTool(BaseTool):
    execution_target = "server"

    def _client(self, ctx: ToolContext) -> GoogleGmailClient:
        if ctx.google_credentials is None:
            raise RuntimeError("Google credentials not available")
        return GoogleGmailClient(ctx.google_credentials)


class SearchEmailsTool(_GmailTool):
    name = "google_gmail.search_emails"
    description = (
        "Search the user's Gmail inbox using Gmail search syntax. "
        "Returns subject, sender, date, snippet, and whether the message has attachments."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Gmail search query (e.g. 'from:erica subject:invoice')",
                },
                "max_results": {
                    "type": "integer",
                    "default": 10,
                    "description": "Maximum number of results to return",
                },
            },
            "required": ["query"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        messages = client.search_messages(
            query=args["query"],
            max_results=args.get("max_results", 10),
        )
        return {"messages": messages, "count": len(messages)}


class ReadEmailTool(_GmailTool):
    name = "google_gmail.read_email"
    description = (
        "Read the full body of an email by its message_id. "
        "Body is truncated to 8K characters to fit in context."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "message_id": {
                    "type": "string",
                    "description": "The Gmail message ID to read",
                },
            },
            "required": ["message_id"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        message = client.get_message(args["message_id"])
        return message


class ListAttachmentsTool(_GmailTool):
    name = "google_gmail.list_attachments"
    description = (
        "List all attachments for a given email message. "
        "Returns attachment_id, filename, mime_type, and size for each."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "message_id": {
                    "type": "string",
                    "description": "The Gmail message ID to list attachments for",
                },
            },
            "required": ["message_id"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        attachments = client.list_attachments(args["message_id"])
        return {"attachments": attachments, "count": len(attachments)}


class GetAttachmentTool(_GmailTool):
    name = "google_gmail.get_attachment"
    description = (
        "Download an email attachment and return a temporary URL to access it. "
        "The URL expires after 30 minutes."
    )

    def parameters_schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "message_id": {
                    "type": "string",
                    "description": "The Gmail message ID containing the attachment",
                },
                "attachment_id": {
                    "type": "string",
                    "description": "The attachment ID from list_attachments",
                },
            },
            "required": ["message_id", "attachment_id"],
        }

    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        client = self._client(context)
        raw_bytes, filename, mime_type = client.download_attachment(
            args["message_id"], args["attachment_id"]
        )
        stored = store_attachment(raw_bytes, filename, mime_type, context.user_id)
        return {
            "id": stored["id"],
            "filename": filename,
            "mime_type": mime_type,
            "size": len(raw_bytes),
            "url": stored["url"],
        }


_TOOLS = [
    SearchEmailsTool(),
    ReadEmailTool(),
    ListAttachmentsTool(),
    GetAttachmentTool(),
]

for _t in _TOOLS:
    register_tool(_t)
