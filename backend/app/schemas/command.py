from __future__ import annotations

from pydantic import BaseModel, Field

from app.schemas.action_plan import ActionPlan
from app.schemas.device import DeviceAction, DeviceActionResult


class CommandRequest(BaseModel):
    transcript: str = Field(..., min_length=1, max_length=5000, description="Speech-to-text transcript")
    timezone: str = Field(default="UTC", max_length=64)
    locale: str = Field(default="en-US", max_length=16)
    linked_providers: list[str] = Field(
        default_factory=lambda: ["google_calendar"],
        description="Linked calendar providers, e.g. google_calendar, ios_eventkit",
        max_length=10,
    )
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    image_data: str | None = Field(default=None, max_length=7_000_000, description="Base64 JPEG, max ~5MB")
    platform: str | None = Field(default=None, max_length=16, description="Client platform: ios or macos")


class Attachment(BaseModel):
    id: str
    filename: str
    mime_type: str
    url: str
    size: int


class CommandResponse(BaseModel):
    spoken_response: str
    action_plan: ActionPlan | None = None
    device_actions: list[DeviceAction] = Field(default_factory=list)
    requires_confirmation: bool = False
    confirmation_prompt: str | None = None
    plan_id: str | None = None
    attachments: list[Attachment] = Field(default_factory=list)
    updated_user_name: str | None = None
    remaining_requests: int | None = None
    clarification: "ClarificationResponse | None" = None
    detected_language: str | None = None


class ConfirmRequest(BaseModel):
    plan_id: str


class DeviceResultRequest(BaseModel):
    plan_id: str
    results: list[DeviceActionResult]


class ClarificationResponse(BaseModel):
    spoken_response: str
    question: str
    options: list[str] = Field(default_factory=list)


class VerificationResult(BaseModel):
    matched: bool
    discrepancies: list[str] = Field(default_factory=list)
