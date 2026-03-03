"""Proactive notifications API — poll for pending notifications, mark as delivered."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.proactive_notification import ProactiveNotification
from app.models.user import User

log = structlog.get_logger()

router = APIRouter()


class PendingNotificationResponse(BaseModel):
    id: str
    title: str
    body: str
    suggested_actions: list[str]
    fire_at: str


class DeliveredRequest(BaseModel):
    ids: list[str]


@router.get("/pending")
async def get_pending_notifications(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[PendingNotificationResponse]:
    now = datetime.now(UTC)
    result = await db.execute(
        select(ProactiveNotification).where(
            and_(
                ProactiveNotification.user_id == user.id,
                ProactiveNotification.delivered == False,  # noqa: E712
                ProactiveNotification.fire_at <= now,
            )
        ).order_by(ProactiveNotification.fire_at)
    )
    notifications = result.scalars().all()
    return [
        PendingNotificationResponse(
            id=str(n.id),
            title=n.title,
            body=n.body,
            suggested_actions=n.suggested_actions or [],
            fire_at=n.fire_at.isoformat(),
        )
        for n in notifications
    ]


@router.post("/delivered")
async def mark_delivered(
    body: DeliveredRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, str]:
    for nid in body.ids:
        try:
            uid = UUID(nid)
        except ValueError:
            continue
        result = await db.execute(
            select(ProactiveNotification).where(
                and_(
                    ProactiveNotification.id == uid,
                    ProactiveNotification.user_id == user.id,
                )
            )
        )
        notification = result.scalar_one_or_none()
        if notification:
            notification.delivered = True

    await db.commit()
    return {"status": "ok"}
