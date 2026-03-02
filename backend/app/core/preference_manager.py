from __future__ import annotations

from typing import Any

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user_preference import UserPreference

log = structlog.get_logger()


class PreferenceManager:
    """Manages user preferences stored in the database."""

    def __init__(self, db: AsyncSession, user_id: str) -> None:
        self._db = db
        self._user_id = user_id

    async def get_all(self) -> dict[str, str]:
        """Return all preferences as {key: value}."""
        result = await self._db.execute(
            select(UserPreference)
            .where(UserPreference.user_id == self._user_id)
            .order_by(UserPreference.key)
        )
        prefs = result.scalars().all()
        return {p.key: p.value for p in prefs}

    async def get(self, key: str) -> str | None:
        """Return a single preference value or None."""
        result = await self._db.execute(
            select(UserPreference)
            .where(UserPreference.user_id == self._user_id, UserPreference.key == key)
        )
        pref = result.scalar_one_or_none()
        return pref.value if pref else None

    async def set(
        self,
        key: str,
        value: str,
        source: str = "explicit",
        confidence: float = 1.0,
    ) -> None:
        """Upsert a preference."""
        result = await self._db.execute(
            select(UserPreference)
            .where(UserPreference.user_id == self._user_id, UserPreference.key == key)
        )
        pref = result.scalar_one_or_none()

        if pref is None:
            pref = UserPreference(
                user_id=self._user_id,
                key=key,
                value=value,
                source=source,
                confidence=confidence,
            )
            self._db.add(pref)
        else:
            pref.value = value
            pref.source = source
            pref.confidence = confidence

        await self._db.commit()
        log.debug("preference.set", user_id=self._user_id, key=key, source=source)

    async def delete(self, key: str) -> bool:
        """Delete a preference. Returns True if it existed."""
        result = await self._db.execute(
            select(UserPreference)
            .where(UserPreference.user_id == self._user_id, UserPreference.key == key)
        )
        pref = result.scalar_one_or_none()
        if pref:
            await self._db.delete(pref)
            await self._db.commit()
            return True
        return False

    @staticmethod
    def build_context_block(prefs: dict[str, str]) -> str:
        """Format preferences for injection into the system prompt."""
        if not prefs:
            return ""
        lines = [f"- {k}: {v}" for k, v in prefs.items()]
        return "## User preferences\n" + "\n".join(lines)
