from __future__ import annotations

import json
from datetime import datetime
from typing import Any

import structlog
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

from app.config import settings
from app.dependencies import get_fernet

log = structlog.get_logger()


def credentials_from_encrypted(encrypted: str) -> Credentials:
    fernet = get_fernet()
    data = json.loads(fernet.decrypt(encrypted.encode()).decode())
    return Credentials(
        token=data["token"],
        refresh_token=data.get("refresh_token"),
        token_uri=data.get("token_uri", "https://oauth2.googleapis.com/token"),
        client_id=data.get("client_id", settings.google_client_id),
        client_secret=data.get("client_secret", settings.google_client_secret),
        scopes=data.get("scopes"),
    )


def _service(credentials: Credentials):
    return build("calendar", "v3", credentials=credentials)


def _dt_body(dt: datetime) -> dict[str, str]:
    if dt.tzinfo is None:
        return {"dateTime": dt.isoformat(), "timeZone": "UTC"}
    return {"dateTime": dt.isoformat()}


class GoogleCalendarClient:
    def __init__(self, credentials: Credentials):
        self._creds = credentials
        self._svc = _service(credentials)

    def list_events(
        self,
        time_min: datetime,
        time_max: datetime,
        query: str | None = None,
        calendar_id: str = "primary",
        max_results: int = 50,
    ) -> list[dict[str, Any]]:
        kwargs: dict[str, Any] = {
            "calendarId": calendar_id,
            "timeMin": time_min.isoformat() + "Z"
            if time_min.tzinfo is None
            else time_min.isoformat(),
            "timeMax": time_max.isoformat() + "Z"
            if time_max.tzinfo is None
            else time_max.isoformat(),
            "maxResults": max_results,
            "singleEvents": True,
            "orderBy": "startTime",
        }
        if query:
            kwargs["q"] = query

        results = self._svc.events().list(**kwargs).execute()
        return results.get("items", [])

    def create_event(
        self,
        title: str,
        start: datetime,
        end: datetime,
        calendar_id: str = "primary",
        attendees: list[str] | None = None,
        location: str | None = None,
        description: str | None = None,
        send_updates: str = "none",
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "summary": title,
            "start": _dt_body(start),
            "end": _dt_body(end),
        }
        if attendees:
            body["attendees"] = [{"email": e} for e in attendees]
        if location:
            body["location"] = location
        if description:
            body["description"] = description

        event = (
            self._svc.events()
            .insert(calendarId=calendar_id, body=body, sendUpdates=send_updates)
            .execute()
        )
        log.info("google_calendar.create_event", event_id=event["id"], title=title)
        return event

    def update_event(
        self,
        event_id: str,
        patch_fields: dict[str, Any],
        calendar_id: str = "primary",
        send_updates: str = "none",
    ) -> dict[str, Any]:
        event = (
            self._svc.events()
            .patch(
                calendarId=calendar_id,
                eventId=event_id,
                body=patch_fields,
                sendUpdates=send_updates,
            )
            .execute()
        )
        log.info("google_calendar.update_event", event_id=event_id)
        return event

    def delete_event(
        self,
        event_id: str,
        calendar_id: str = "primary",
        send_updates: str = "none",
    ) -> None:
        self._svc.events().delete(
            calendarId=calendar_id, eventId=event_id, sendUpdates=send_updates
        ).execute()
        log.info("google_calendar.delete_event", event_id=event_id)

    def freebusy(
        self,
        time_min: datetime,
        time_max: datetime,
        calendar_ids: list[str] | None = None,
    ) -> dict[str, Any]:
        ids = calendar_ids or ["primary"]
        body = {
            "timeMin": time_min.isoformat() + "Z"
            if time_min.tzinfo is None
            else time_min.isoformat(),
            "timeMax": time_max.isoformat() + "Z"
            if time_max.tzinfo is None
            else time_max.isoformat(),
            "items": [{"id": cid} for cid in ids],
        }
        return self._svc.freebusy().query(body=body).execute()

    def quick_add(
        self,
        text: str,
        calendar_id: str = "primary",
    ) -> dict[str, Any]:
        event = self._svc.events().quickAdd(calendarId=calendar_id, text=text).execute()
        log.info("google_calendar.quick_add", event_id=event["id"], text=text)
        return event

    def get_event(self, event_id: str, calendar_id: str = "primary") -> dict[str, Any]:
        return self._svc.events().get(calendarId=calendar_id, eventId=event_id).execute()
