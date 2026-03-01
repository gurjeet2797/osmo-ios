from __future__ import annotations

import uuid
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, Field


class RiskLevel(StrEnum):
    low = "low"
    medium = "medium"
    high = "high"


class ActionStep(BaseModel):
    tool_name: str = Field(
        ..., description='Qualified tool name, e.g. "google_calendar.create_event"'
    )
    args: dict[str, Any] = Field(default_factory=dict)
    risk_level: RiskLevel = RiskLevel.low
    requires_confirmation: bool = False
    confirmation_phrase: str | None = None
    idempotency_key: str = Field(default_factory=lambda: uuid.uuid4().hex)
    execution_target: Literal["server", "device"] = "server"
    tool_call_id: str | None = None


class ActionPlan(BaseModel):
    plan_id: str = Field(default_factory=lambda: uuid.uuid4().hex)
    user_intent: str
    timezone: str = "UTC"
    locale: str = "en-US"
    steps: list[ActionStep] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))

    @property
    def needs_confirmation(self) -> bool:
        return any(s.requires_confirmation for s in self.steps)

    @property
    def max_risk(self) -> RiskLevel:
        if not self.steps:
            return RiskLevel.low
        order = {RiskLevel.low: 0, RiskLevel.medium: 1, RiskLevel.high: 2}
        return max(self.steps, key=lambda s: order[s.risk_level]).risk_level
