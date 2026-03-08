from __future__ import annotations

import hashlib
import uuid
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.user import User
from app.models.user_fact import UserFact

log = structlog.get_logger()

router = APIRouter()


class MessageIndexRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=50_000)
    source: str = Field(default="share_extension", max_length=32)
    timestamp: str | None = None


class MessageIndexResponse(BaseModel):
    indexed: bool
    facts_created: int


@router.post("/index", response_model=MessageIndexResponse)
async def index_messages(
    body: MessageIndexRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Index shared message text as user facts for scheduling context."""
    # Deduplicate by hashing the text content
    text_hash = hashlib.sha256(body.text.encode()).hexdigest()[:32]
    fact_key = f"message_context:{text_hash}"

    # Check if already indexed
    existing = await db.execute(
        select(UserFact).where(
            UserFact.user_id == user.id,
            UserFact.key == fact_key,
        )
    )
    if existing.scalar_one_or_none():
        return MessageIndexResponse(indexed=True, facts_created=0)

    # Store as a user fact
    fact = UserFact(
        id=uuid.uuid4(),
        user_id=user.id,
        key=fact_key,
        value=body.text[:10_000],  # cap storage
        category="message_context",
        source=body.source,
        confidence=0.9,
    )
    db.add(fact)
    await db.commit()

    log.info(
        "message.indexed",
        user_id=str(user.id),
        source=body.source,
        text_length=len(body.text),
    )

    return MessageIndexResponse(indexed=True, facts_created=1)


@router.get("/context")
async def get_message_context(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = 20,
):
    """Retrieve indexed message context for the planner."""
    result = await db.execute(
        select(UserFact)
        .where(
            UserFact.user_id == user.id,
            UserFact.category == "message_context",
        )
        .order_by(UserFact.created_at.desc())
        .limit(limit)
    )
    facts = result.scalars().all()
    return {
        "messages": [
            {
                "text": f.value,
                "source": f.source,
                "indexed_at": f.created_at.isoformat() if f.created_at else None,
            }
            for f in facts
        ]
    }
