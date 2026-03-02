from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Literal

from app.schemas.command import VerificationResult


class BaseTool(ABC):
    name: str
    description: str
    execution_target: Literal["server", "device"] = "server"

    @abstractmethod
    async def execute(self, args: dict[str, Any], context: ToolContext) -> dict[str, Any]:
        """Execute the tool and return the result dict."""

    async def verify(
        self, args: dict[str, Any], result: dict[str, Any], context: ToolContext
    ) -> VerificationResult:
        """Optional: verify the result by reading back. Default: trust the result."""
        return VerificationResult(matched=True)

    def to_llm_spec(self) -> dict[str, Any]:
        """Return the tool specification for the LLM function-calling interface."""
        return {
            "name": self.name,
            "description": self.description,
            "execution_target": self.execution_target,
            "parameters": self.parameters_schema(),
        }

    def to_anthropic_spec(self, name_override: str | None = None) -> dict[str, Any]:
        """Return the tool specification for the Anthropic tool-use interface."""
        return {
            "name": name_override or self.name,
            "description": self.description,
            "input_schema": self.parameters_schema(),
        }

    @abstractmethod
    def parameters_schema(self) -> dict[str, Any]:
        """JSON Schema for the tool's arguments."""


class ToolContext:
    """Runtime context passed to every tool execution."""

    def __init__(
        self,
        user_id: str,
        google_credentials: Any | None = None,
        timezone: str = "UTC",
        db: Any | None = None,
    ):
        self.user_id = user_id
        self.google_credentials = google_credentials
        self.timezone = timezone
        self.db = db
