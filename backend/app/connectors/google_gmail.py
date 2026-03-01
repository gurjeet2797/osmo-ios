from __future__ import annotations

import base64
import email.utils
import re
from typing import Any

import structlog
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

log = structlog.get_logger()

MAX_BODY_CHARS = 8000


def _service(credentials: Credentials):
    return build("gmail", "v1", credentials=credentials)


def _decode_body(payload: dict[str, Any]) -> str:
    """Recursively extract plain-text body from a Gmail message payload."""
    mime_type = payload.get("mimeType", "")
    parts = payload.get("parts", [])

    # Direct body on this part
    if mime_type == "text/plain":
        data = payload.get("body", {}).get("data", "")
        if data:
            return base64.urlsafe_b64decode(data).decode("utf-8", errors="replace")

    # Multipart: recurse and prefer text/plain
    if parts:
        # First pass: look for text/plain
        for part in parts:
            if part.get("mimeType") == "text/plain":
                text = _decode_body(part)
                if text:
                    return text
        # Second pass: look for text/html and strip tags
        for part in parts:
            if part.get("mimeType") == "text/html":
                text = _decode_body(part)
                if text:
                    return _strip_html(text)
        # Third pass: recurse into multipart children
        for part in parts:
            text = _decode_body(part)
            if text:
                return text

    # Fallback: HTML body at top level
    if mime_type == "text/html":
        data = payload.get("body", {}).get("data", "")
        if data:
            html = base64.urlsafe_b64decode(data).decode("utf-8", errors="replace")
            return _strip_html(html)

    return ""


def _strip_html(html: str) -> str:
    """Rough HTML-to-text conversion."""
    text = re.sub(r"<br\s*/?>", "\n", html, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"&nbsp;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"&lt;", "<", text)
    text = re.sub(r"&gt;", ">", text)
    text = re.sub(r"&#\d+;", "", text)
    return text.strip()


def _get_header(headers: list[dict[str, str]], name: str) -> str:
    """Get a header value by name (case-insensitive)."""
    for h in headers:
        if h.get("name", "").lower() == name.lower():
            return h.get("value", "")
    return ""


class GoogleGmailClient:
    def __init__(self, credentials: Credentials):
        self._creds = credentials
        self._svc = _service(credentials)

    def search_messages(
        self,
        query: str,
        max_results: int = 10,
    ) -> list[dict[str, Any]]:
        """Search Gmail with query syntax. Returns metadata for each message."""
        results = (
            self._svc.users()
            .messages()
            .list(userId="me", q=query, maxResults=max_results)
            .execute()
        )
        message_ids = results.get("messages", [])
        if not message_ids:
            return []

        messages = []
        for msg_ref in message_ids:
            msg = (
                self._svc.users()
                .messages()
                .get(userId="me", id=msg_ref["id"], format="metadata",
                     metadataHeaders=["Subject", "From", "Date", "To"])
                .execute()
            )
            headers = msg.get("payload", {}).get("headers", [])
            # Check if message has attachments
            has_attachments = _has_attachments(msg.get("payload", {}))

            messages.append({
                "message_id": msg["id"],
                "thread_id": msg.get("threadId", ""),
                "subject": _get_header(headers, "Subject"),
                "from": _get_header(headers, "From"),
                "to": _get_header(headers, "To"),
                "date": _get_header(headers, "Date"),
                "snippet": msg.get("snippet", ""),
                "has_attachments": has_attachments,
            })

        log.info("google_gmail.search_messages", query=query, count=len(messages))
        return messages

    def get_message(self, message_id: str) -> dict[str, Any]:
        """Get full message content by ID. Body is truncated to MAX_BODY_CHARS."""
        msg = (
            self._svc.users()
            .messages()
            .get(userId="me", id=message_id, format="full")
            .execute()
        )
        headers = msg.get("payload", {}).get("headers", [])
        body = _decode_body(msg.get("payload", {}))
        if len(body) > MAX_BODY_CHARS:
            body = body[:MAX_BODY_CHARS] + "\n... [truncated]"

        return {
            "message_id": msg["id"],
            "thread_id": msg.get("threadId", ""),
            "subject": _get_header(headers, "Subject"),
            "from": _get_header(headers, "From"),
            "to": _get_header(headers, "To"),
            "date": _get_header(headers, "Date"),
            "body": body,
            "has_attachments": _has_attachments(msg.get("payload", {})),
        }

    def list_attachments(self, message_id: str) -> list[dict[str, Any]]:
        """List all attachments for a message."""
        msg = (
            self._svc.users()
            .messages()
            .get(userId="me", id=message_id, format="full")
            .execute()
        )
        return _collect_attachments(msg.get("payload", {}), message_id)

    def download_attachment(
        self, message_id: str, attachment_id: str
    ) -> tuple[bytes, str, str]:
        """Download an attachment. Returns (raw_bytes, filename, mime_type)."""
        # First get the message to find filename/mime from the part
        msg = (
            self._svc.users()
            .messages()
            .get(userId="me", id=message_id, format="full")
            .execute()
        )
        attachments = _collect_attachments(msg.get("payload", {}), message_id)
        filename = "attachment"
        mime_type = "application/octet-stream"
        for att in attachments:
            if att["attachment_id"] == attachment_id:
                filename = att["filename"]
                mime_type = att["mime_type"]
                break

        att_data = (
            self._svc.users()
            .messages()
            .attachments()
            .get(userId="me", messageId=message_id, id=attachment_id)
            .execute()
        )
        raw = base64.urlsafe_b64decode(att_data["data"])
        log.info(
            "google_gmail.download_attachment",
            message_id=message_id,
            filename=filename,
            size=len(raw),
        )
        return raw, filename, mime_type


def _has_attachments(payload: dict[str, Any]) -> bool:
    """Check if any part has a non-inline attachment."""
    parts = payload.get("parts", [])
    for part in parts:
        if part.get("filename"):
            return True
        if _has_attachments(part):
            return True
    return False


def _collect_attachments(
    payload: dict[str, Any], message_id: str
) -> list[dict[str, Any]]:
    """Recursively collect attachment metadata from message parts."""
    attachments: list[dict[str, Any]] = []
    parts = payload.get("parts", [])
    for part in parts:
        filename = part.get("filename", "")
        body = part.get("body", {})
        attachment_id = body.get("attachmentId")
        if filename and attachment_id:
            attachments.append({
                "attachment_id": attachment_id,
                "filename": filename,
                "mime_type": part.get("mimeType", "application/octet-stream"),
                "size": body.get("size", 0),
                "message_id": message_id,
            })
        # Recurse into nested parts
        attachments.extend(_collect_attachments(part, message_id))
    return attachments
