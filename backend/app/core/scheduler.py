from __future__ import annotations

import structlog
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

log = structlog.get_logger()

_scheduler: AsyncIOScheduler | None = None


def start_scheduler() -> AsyncIOScheduler:
    """Create and start the background job scheduler."""
    global _scheduler

    from app.core.jobs import analyze_habits
    from app.core.briefing import prepare_all_briefings

    _scheduler = AsyncIOScheduler()

    _scheduler.add_job(
        analyze_habits,
        CronTrigger(hour=3, minute=0),  # Daily at 3 AM UTC
        id="analyze_habits",
        replace_existing=True,
    )
    _scheduler.add_job(
        prepare_all_briefings,
        CronTrigger(hour=5, minute=0),  # Daily at 5 AM UTC
        id="morning_briefings",
        replace_existing=True,
    )

    _scheduler.start()
    log.info("scheduler.started", jobs=["analyze_habits", "morning_briefings"])
    return _scheduler


def stop_scheduler() -> None:
    """Gracefully stop the scheduler."""
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        log.info("scheduler.stopped")
