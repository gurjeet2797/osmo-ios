from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class DeviceAction(BaseModel):
    """An action the iOS app must execute locally (e.g. EventKit writes)."""

    action_id: str
    tool_name: str
    args: dict[str, Any] = Field(default_factory=dict)
    idempotency_key: str


class DeviceActionResult(BaseModel):
    """Result reported back by the iOS app after executing a DeviceAction."""

    action_id: str
    idempotency_key: str
    success: bool
    result: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None
