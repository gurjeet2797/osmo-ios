"""User knowledge store — accumulates facts about the user over time.

Facts are extracted from tool results (emails, calendar events, etc.) and
injected into every system prompt so the LLM has rich context about the user.
"""

from __future__ import annotations

from typing import Any

import structlog
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user_fact import UserFact

log = structlog.get_logger()

# Max facts injected into the system prompt (most-referenced first)
MAX_PROMPT_FACTS = 60


class KnowledgeManager:
    """Read/write interface for the user fact store."""

    def __init__(self, db: AsyncSession, user_id: str) -> None:
        self._db = db
        self._user_id = user_id

    # ------------------------------------------------------------------
    # Reads
    # ------------------------------------------------------------------

    async def get_all(self, limit: int = MAX_PROMPT_FACTS) -> list[dict[str, str]]:
        """Return the most relevant facts, ordered by hit_count desc then recency."""
        result = await self._db.execute(
            select(UserFact)
            .where(UserFact.user_id == self._user_id)
            .order_by(UserFact.hit_count.desc(), UserFact.updated_at.desc())
            .limit(limit)
        )
        return [
            {"key": f.key, "value": f.value, "category": f.category}
            for f in result.scalars().all()
        ]

    async def search(self, query: str, category: str | None = None, limit: int = 20) -> list[dict[str, str]]:
        """Search facts by keyword in key or value. Optional category filter."""
        q = query.lower()
        stmt = (
            select(UserFact)
            .where(UserFact.user_id == self._user_id)
            .where(
                UserFact.key.ilike(f"%{q}%") | UserFact.value.ilike(f"%{q}%")
            )
            .order_by(UserFact.hit_count.desc(), UserFact.updated_at.desc())
            .limit(limit)
        )
        if category:
            stmt = stmt.where(UserFact.category == category)
        result = await self._db.execute(stmt)
        facts = result.scalars().all()

        # Bump hit_count for returned facts (they're being used)
        if facts:
            ids = [f.id for f in facts]
            await self._db.execute(
                update(UserFact)
                .where(UserFact.id.in_(ids))
                .values(hit_count=UserFact.hit_count + 1)
            )
            await self._db.commit()

        return [
            {"key": f.key, "value": f.value, "category": f.category}
            for f in facts
        ]

    # ------------------------------------------------------------------
    # Writes
    # ------------------------------------------------------------------

    async def store(
        self,
        key: str,
        value: str,
        category: str = "general",
        source: str = "extracted",
        confidence: float = 0.8,
    ) -> bool:
        """Upsert a fact. Returns True if it was new, False if updated."""
        result = await self._db.execute(
            select(UserFact).where(
                UserFact.user_id == self._user_id,
                UserFact.key == key,
            )
        )
        existing = result.scalar_one_or_none()

        if existing is None:
            fact = UserFact(
                user_id=self._user_id,
                key=key,
                value=value,
                category=category,
                source=source,
                confidence=confidence,
            )
            self._db.add(fact)
            await self._db.commit()
            log.info("knowledge.stored", user_id=self._user_id, key=key, category=category)
            return True
        else:
            # Update if the new value is more confident or the source is better
            should_update = (
                confidence > existing.confidence
                or source == "explicit"
                or (source == "extracted" and existing.source == "inferred")
                or value != existing.value  # always keep latest data
            )
            if should_update:
                existing.value = value
                existing.source = source
                existing.confidence = max(confidence, existing.confidence)
                existing.hit_count += 1
                await self._db.commit()
                log.debug("knowledge.updated", user_id=self._user_id, key=key)
            return False

    async def store_many(self, facts: list[dict[str, Any]]) -> int:
        """Batch-store multiple facts. Returns count of new facts."""
        new_count = 0
        for f in facts:
            is_new = await self.store(
                key=f["key"],
                value=f["value"],
                category=f.get("category", "general"),
                source=f.get("source", "extracted"),
                confidence=f.get("confidence", 0.8),
            )
            if is_new:
                new_count += 1
        return new_count

    async def delete(self, key: str) -> bool:
        """Delete a fact by key."""
        result = await self._db.execute(
            select(UserFact).where(
                UserFact.user_id == self._user_id,
                UserFact.key == key,
            )
        )
        fact = result.scalar_one_or_none()
        if fact:
            self._db.delete(fact)
            await self._db.commit()
            return True
        return False

    # ------------------------------------------------------------------
    # Prompt building
    # ------------------------------------------------------------------

    @staticmethod
    def build_context_block(facts: list[dict[str, str]]) -> str:
        """Format facts for injection into the system prompt."""
        if not facts:
            return ""

        # Group by category for readability
        by_cat: dict[str, list[str]] = {}
        for f in facts:
            cat = f["category"]
            by_cat.setdefault(cat, []).append(f"- {f['key']}: {f['value']}")

        # Category display order
        order = ["contact", "personal", "work", "location", "habit", "general"]
        lines = ["## What you know about this user"]
        for cat in order:
            if cat in by_cat:
                cat_title = cat.replace("_", " ").title()
                lines.append(f"### {cat_title}")
                lines.extend(by_cat[cat])
        # Any categories not in order
        for cat, items in by_cat.items():
            if cat not in order:
                lines.append(f"### {cat.title()}")
                lines.extend(items)

        return "\n".join(lines)
