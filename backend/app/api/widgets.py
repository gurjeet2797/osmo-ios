"""Widget data endpoints for home screen widgets."""
from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Annotated, Any

import structlog
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.connectors.google_calendar import credentials_from_encrypted
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.user import User

log = structlog.get_logger()

router = APIRouter()


class EmailSummary(BaseModel):
    unread_count: int = 0
    top_emails: list[dict[str, str]] = []  # [{sender, subject, snippet}]


class CommuteEstimate(BaseModel):
    duration: str | None = None
    duration_seconds: int | None = None
    distance: str | None = None
    destination: str | None = None
    travel_mode: str = "DRIVE"


class WidgetData(BaseModel):
    email: EmailSummary | None = None
    commute: CommuteEstimate | None = None


@router.get("/data")
async def get_widget_data(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    widgets: str = Query(default="email,commute", description="Comma-separated widget types"),
) -> WidgetData:
    requested = {w.strip() for w in widgets.split(",")}
    result = WidgetData()

    if "email" in requested and user.google_tokens_encrypted:
        result.email = await _fetch_email_summary(user)

    if "commute" in requested and user.google_tokens_encrypted:
        result.commute = await _fetch_commute(user, db)

    return result


async def _fetch_email_summary(user: User) -> EmailSummary:
    """Fetch unread email count and top 3 subjects."""
    try:
        from app.connectors.google_gmail import GoogleGmailClient
        creds = credentials_from_encrypted(user.google_tokens_encrypted)
        client = GoogleGmailClient(creds)
        results = client.search_messages("is:unread", max_results=5)

        top_emails = []
        for msg in results[:3]:
            top_emails.append({
                "sender": msg.get("from", "Unknown").split("<")[0].strip(),
                "subject": msg.get("subject", "(no subject)"),
                "snippet": msg.get("snippet", "")[:80],
            })

        return EmailSummary(
            unread_count=len(results),
            top_emails=top_emails,
        )
    except Exception:
        log.debug("widget.email_failed", user_id=str(user.id), exc_info=True)
        return EmailSummary()


async def _fetch_commute(user: User, db: AsyncSession) -> CommuteEstimate:
    """Fetch commute estimate using stored preferences or knowledge facts."""
    try:
        from app.core.preference_manager import PreferenceManager
        from app.core.knowledge import KnowledgeManager
        mgr = PreferenceManager(db, str(user.id))
        km = KnowledgeManager(db, str(user.id))
        prefs = await mgr.get_all()

        # Check preferences first, then fall back to knowledge facts
        destination = prefs.get("work_address") or prefs.get("commute_destination")
        origin = prefs.get("home_address") or prefs.get("commute_origin")

        if not destination or not origin:
            try:
                facts = await km.get_all()
                fact_map = {f.key: f.value for f in facts}
                if not destination:
                    # Try exact keys, then fuzzy match on any key containing "work" and "address"
                    destination = fact_map.get("work_address") or fact_map.get("work-address")
                    if not destination:
                        for k, v in fact_map.items():
                            if "work" in k.lower() and "address" in k.lower():
                                destination = v
                                break
                if not origin:
                    origin = fact_map.get("home_address") or fact_map.get("home-address")
                    if not origin:
                        for k, v in fact_map.items():
                            if "home" in k.lower() and "address" in k.lower():
                                origin = v
                                break
            except Exception:
                log.debug("widget.commute_facts_failed", exc_info=True)

        if not destination:
            return CommuteEstimate(destination=None)

        from app.connectors.google_routes import GoogleRoutesClient
        routes_client = GoogleRoutesClient(api_key=settings.google_routes_api_key)
        route = routes_client.compute_route(
            origin=origin or "current location",
            destination=destination,
            travel_mode="DRIVE",
        )

        return CommuteEstimate(
            duration=route.get("duration"),
            duration_seconds=route.get("duration_seconds"),
            distance=route.get("distance"),
            destination=destination,
        )
    except Exception:
        log.debug("widget.commute_failed", user_id=str(user.id), exc_info=True)
        return CommuteEstimate()
