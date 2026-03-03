from contextlib import asynccontextmanager

import sentry_sdk
import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import attachments, auth, calendar, command, health, notifications, openclaw, preferences, subscription, suggestions, widgets
from app.config import settings
from app.db.session import engine, redis_pool

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.dev.ConsoleRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(0),
)

if settings.sentry_dsn:
    sentry_sdk.init(dsn=settings.sentry_dsn, traces_sample_rate=0.2)


@asynccontextmanager
async def lifespan(app: FastAPI):
    log = structlog.get_logger()
    from urllib.parse import urlparse
    db_host = urlparse(settings.database_url).hostname or "unknown"
    log.info("Starting Osmo backend", db_host=db_host, environment=settings.environment)

    # Start background job scheduler
    from app.core.scheduler import start_scheduler, stop_scheduler
    try:
        start_scheduler()
    except Exception:
        log.warning("scheduler.start_failed", exc_info=True)

    yield

    try:
        stop_scheduler()
    except Exception:
        log.warning("scheduler.stop_failed", exc_info=True)

    # Close OpenClaw connection pool
    from app.core.openclaw_client import openclaw_client
    try:
        await openclaw_client.close()
    except Exception:
        log.warning("openclaw.close_failed", exc_info=True)

    await engine.dispose()
    await redis_pool.aclose()


app = FastAPI(
    title="Osmo Command Center",
    version="0.1.0",
    lifespan=lifespan,
)

origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()] if settings.allowed_origins else ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(command.router, prefix="/command", tags=["command"])
app.include_router(calendar.router, prefix="/calendar", tags=["calendar"])
app.include_router(attachments.router, prefix="/attachments", tags=["attachments"])
app.include_router(suggestions.router, prefix="/suggestions", tags=["suggestions"])
app.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
app.include_router(openclaw.router, prefix="/openclaw", tags=["openclaw"])
app.include_router(preferences.router, prefix="/preferences", tags=["preferences"])
app.include_router(subscription.router, prefix="/subscription", tags=["subscription"])
app.include_router(widgets.router, prefix="/widgets", tags=["widgets"])
