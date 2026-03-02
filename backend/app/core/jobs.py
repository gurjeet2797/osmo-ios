from __future__ import annotations

from collections import Counter
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import distinct, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import async_session_factory
from app.models.command_history import CommandHistory
from app.models.user_preference import UserPreference

log = structlog.get_logger()


async def analyze_habits() -> None:
    """Nightly job: analyze command history and store inferred preferences.

    Runs for each active user (anyone with commands in the last 7 days).
    Extracts patterns and stores as inferred preferences with confidence scores.
    """
    log.info("job.analyze_habits.start")

    async with async_session_factory() as db:
        cutoff = datetime.now(UTC) - timedelta(days=7)

        # Find active users
        result = await db.execute(
            select(distinct(CommandHistory.user_id)).where(
                CommandHistory.created_at >= cutoff
            )
        )
        user_ids = [row[0] for row in result.all()]

        for user_id in user_ids:
            try:
                await _analyze_user(db, str(user_id), cutoff)
            except Exception:
                log.warning("job.analyze_habits.user_failed", user_id=str(user_id), exc_info=True)

    log.info("job.analyze_habits.done", users_analyzed=len(user_ids))


async def _analyze_user(db: AsyncSession, user_id: str, cutoff: datetime) -> None:
    """Analyze a single user's command patterns."""
    result = await db.execute(
        select(CommandHistory)
        .where(CommandHistory.user_id == user_id, CommandHistory.created_at >= cutoff)
        .order_by(CommandHistory.created_at.desc())
    )
    commands = result.scalars().all()

    if len(commands) < 3:
        return  # Too few commands to analyze

    # 1. Tool frequency analysis
    tool_counter: Counter[str] = Counter()
    for cmd in commands:
        if cmd.tool_names:
            for t in cmd.tool_names:
                tool_counter[t] += 1

    # Infer preferred calendar provider
    gcal_count = sum(v for k, v in tool_counter.items() if k.startswith("google_calendar"))
    apple_count = sum(v for k, v in tool_counter.items() if k.startswith("ios_eventkit"))
    if gcal_count + apple_count > 2:
        preferred = "google_calendar" if gcal_count >= apple_count else "apple_calendar"
        confidence = max(gcal_count, apple_count) / (gcal_count + apple_count)
        await _upsert_inferred(db, user_id, "preferred_calendar", preferred, confidence)

    # 2. Time-of-day patterns
    morning_cmds = [c for c in commands if c.hour_of_day is not None and c.hour_of_day < 12]
    afternoon_cmds = [c for c in commands if c.hour_of_day is not None and 12 <= c.hour_of_day < 17]
    evening_cmds = [c for c in commands if c.hour_of_day is not None and c.hour_of_day >= 17]

    if morning_cmds:
        morning_tools = Counter(
            t for c in morning_cmds if c.tool_names for t in c.tool_names
        )
        if morning_tools:
            top = morning_tools.most_common(1)[0][0]
            await _upsert_inferred(
                db, user_id, "morning_routine_action", top,
                morning_tools[top] / len(morning_cmds),
            )

    # 3. Most used features
    if tool_counter:
        top_tools = [name for name, _ in tool_counter.most_common(3)]
        await _upsert_inferred(
            db, user_id, "top_features",
            ", ".join(top_tools), 0.8,
        )

    await db.commit()


async def _upsert_inferred(
    db: AsyncSession,
    user_id: str,
    key: str,
    value: str,
    confidence: float,
) -> None:
    """Insert or update an inferred preference (never overwrite explicit ones)."""
    result = await db.execute(
        select(UserPreference).where(
            UserPreference.user_id == user_id,
            UserPreference.key == key,
        )
    )
    pref = result.scalar_one_or_none()

    if pref is not None:
        # Don't overwrite explicit preferences
        if pref.source == "explicit":
            return
        pref.value = value
        pref.confidence = confidence
    else:
        pref = UserPreference(
            user_id=user_id,
            key=key,
            value=value,
            source="inferred",
            confidence=confidence,
        )
        db.add(pref)
