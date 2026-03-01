from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response

from app.dependencies import get_current_user
from app.models.user import User

router = APIRouter()

EXPIRY_MINUTES = 30

# In-memory store: {id: {data, filename, mime_type, user_id, expires_at}}
_store: dict[str, dict[str, Any]] = {}


def _cleanup_expired() -> None:
    """Remove expired entries from the store."""
    now = datetime.now(UTC)
    expired = [k for k, v in _store.items() if v["expires_at"] < now]
    for k in expired:
        del _store[k]


def store_attachment(
    data: bytes, filename: str, mime_type: str, user_id: str
) -> dict[str, str]:
    """Store attachment data and return {id, url}."""
    _cleanup_expired()
    attachment_id = str(uuid.uuid4())
    _store[attachment_id] = {
        "data": data,
        "filename": filename,
        "mime_type": mime_type,
        "user_id": user_id,
        "expires_at": datetime.now(UTC) + timedelta(minutes=EXPIRY_MINUTES),
    }
    return {
        "id": attachment_id,
        "url": f"/attachments/{attachment_id}",
    }


@router.get("/{attachment_id}")
async def serve_attachment(
    attachment_id: str,
    user: Annotated[User, Depends(get_current_user)],
):
    """Serve a stored attachment file with correct Content-Type."""
    _cleanup_expired()
    entry = _store.get(attachment_id)
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Attachment not found or expired")
    if entry["user_id"] != str(user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Access denied")
    return Response(
        content=entry["data"],
        media_type=entry["mime_type"],
        headers={
            "Content-Disposition": f'inline; filename="{entry["filename"]}"',
        },
    )
