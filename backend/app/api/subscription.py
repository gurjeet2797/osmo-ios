from __future__ import annotations

from typing import Annotated

import structlog
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.user import User

log = structlog.get_logger()

router = APIRouter()


class VerifyReceiptRequest(BaseModel):
    transaction_id: str


class SubscriptionStatusResponse(BaseModel):
    tier: str
    remaining_requests: int | None = None


@router.post("/verify")
async def verify_receipt(
    body: VerifyReceiptRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, str]:
    # TODO: Verify with Apple StoreKit Server API in production
    # For now, trust the client and upgrade the user
    log.info(
        "subscription.verify",
        user_id=str(user.id),
        transaction_id=body.transaction_id,
    )
    user.subscription_tier = "pro"
    await db.commit()
    return {"status": "ok", "tier": "pro"}


@router.get("/status")
async def get_status(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SubscriptionStatusResponse:
    tier = user.subscription_tier or "free"

    # Check if dev email
    dev_emails = [e.strip() for e in settings.dev_emails.split(",") if e.strip()]
    if user.email in dev_emails:
        tier = "dev"

    remaining: int | None = None
    if tier == "free":
        from app.api.command import _count_today_commands
        count = await _count_today_commands(db, str(user.id))
        remaining = max(0, settings.free_daily_limit - count)

    return SubscriptionStatusResponse(tier=tier, remaining_requests=remaining)
