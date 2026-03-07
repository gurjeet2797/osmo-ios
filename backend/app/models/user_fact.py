from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Index, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class UserFact(Base):
    """A single fact about the user, automatically extracted or explicitly stored.

    Categories:
        contact   — people the user interacts with (name, email, phone, address)
        location  — places relevant to the user (home, work, frequented spots)
        personal  — personal details (birthday, pets, family members)
        work      — job title, company, team, projects
        habit     — behavioral patterns (preferred meeting times, routines)
        general   — anything else worth remembering
    """

    __tablename__ = "user_facts"
    __table_args__ = (
        UniqueConstraint("user_id", "key", name="uq_user_facts_user_key"),
        Index("ix_user_facts_user_category", "user_id", "category"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Structured key for deduplication: "contact:erica_humphrey:address"
    key: Mapped[str] = mapped_column(String(256), nullable=False)

    # Human-readable value: "123 Main St, Austin, TX 78701"
    value: Mapped[str] = mapped_column(Text, nullable=False)

    # Category for efficient filtering
    category: Mapped[str] = mapped_column(String(32), nullable=False, default="general")

    # How we learned this: "extracted" (from tool results), "explicit" (user stated it),
    # "inferred" (LLM deduced from context)
    source: Mapped[str] = mapped_column(String(32), default="extracted")

    # Confidence score (1.0 = user stated directly, 0.5-0.9 = extracted from data)
    confidence: Mapped[float] = mapped_column(Float, default=0.8)

    # How many times this fact has been referenced/confirmed (boosts relevance)
    hit_count: Mapped[int] = mapped_column(default=0)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
