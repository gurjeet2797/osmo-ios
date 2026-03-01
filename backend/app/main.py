from contextlib import asynccontextmanager

import sentry_sdk
import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import attachments, auth, calendar, command, health
from app.config import settings
from app.db.session import engine

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
    yield
    await engine.dispose()


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
