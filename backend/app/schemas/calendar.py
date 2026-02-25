from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class CalendarEventBase(BaseModel):
    title: str
    start: datetime
    end: datetime
    location: str | None = None
    description: str | None = None


class GoogleCreateEventArgs(CalendarEventBase):
    calendar_id: str = "primary"
    attendees: list[str] = Field(default_factory=list)
    send_updates: str = "none"


class GoogleUpdateEventArgs(BaseModel):
    event_id: str
    calendar_id: str = "primary"
    patch_fields: dict = Field(default_factory=dict)
    send_updates: str = "none"


class GoogleDeleteEventArgs(BaseModel):
    event_id: str
    calendar_id: str = "primary"
    send_updates: str = "none"


class GoogleListEventsArgs(BaseModel):
    time_min: datetime
    time_max: datetime
    query: str | None = None
    calendar_id: str = "primary"
    max_results: int = 50


class GoogleFreeBusyArgs(BaseModel):
    time_min: datetime
    time_max: datetime
    calendar_ids: list[str] = Field(default_factory=lambda: ["primary"])


class GoogleQuickAddArgs(BaseModel):
    text: str
    calendar_id: str = "primary"


class IOSCreateEventArgs(CalendarEventBase):
    calendar_id: str | None = None
    notes: str | None = None
    alarms: list[int] = Field(
        default_factory=list, description="Alarm offsets in minutes before the event"
    )


class IOSUpdateEventArgs(BaseModel):
    event_identifier: str
    patch_fields: dict = Field(default_factory=dict)


class IOSDeleteEventArgs(BaseModel):
    event_identifier: str


class IOSListEventsArgs(BaseModel):
    start: datetime
    end: datetime
    calendar_ids: list[str] | None = None


class CalendarEvent(CalendarEventBase):
    """Normalized calendar event returned from any provider."""

    id: str
    provider: str
    calendar_id: str | None = None
    attendees: list[str] = Field(default_factory=list)
    html_link: str | None = None
