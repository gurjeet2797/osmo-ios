from __future__ import annotations

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any

import structlog

from app.config import settings

log = structlog.get_logger()


# ---------------------------------------------------------------------------
# Unified response types
# ---------------------------------------------------------------------------

@dataclass
class ToolCall:
    """A single tool call extracted from the LLM response."""

    id: str
    name: str  # internal name (dots restored)
    arguments: dict[str, Any]


@dataclass
class LLMResponse:
    """Provider-agnostic LLM response."""

    text: str | None = None
    tool_calls: list[ToolCall] = field(default_factory=list)
    raw: Any = None  # original provider response


# ---------------------------------------------------------------------------
# Abstract base
# ---------------------------------------------------------------------------

class BaseLLMClient(ABC):
    @abstractmethod
    async def chat(
        self,
        system_prompt: str,
        user_message: str,
        tools: list[dict[str, Any]] | None = None,
        messages: list[dict[str, Any]] | None = None,
    ) -> LLMResponse:
        """Send a message (with optional history) and return a unified response."""

    @abstractmethod
    async def follow_up(
        self,
        system_prompt: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> LLMResponse:
        """Continue a conversation with existing message history."""


# ---------------------------------------------------------------------------
# Anthropic implementation
# ---------------------------------------------------------------------------

class AnthropicLLMClient(BaseLLMClient):
    def __init__(self) -> None:
        from anthropic import AsyncAnthropic

        self._client = AsyncAnthropic(api_key=settings.anthropic_api_key)
        self._model = settings.anthropic_model
        self._max_tokens = settings.anthropic_max_tokens

    async def chat(
        self,
        system_prompt: str,
        user_message: str,
        tools: list[dict[str, Any]] | None = None,
        messages: list[dict[str, Any]] | None = None,
    ) -> LLMResponse:
        # Build message list: optional history + new user message
        msgs: list[dict[str, Any]] = list(messages or [])
        msgs.append({"role": "user", "content": user_message})

        kwargs: dict[str, Any] = {
            "model": self._model,
            "max_tokens": self._max_tokens,
            "system": system_prompt,
            "messages": msgs,
            "temperature": 0.3,
        }
        if tools:
            kwargs["tools"] = tools
            kwargs["tool_choice"] = {"type": "auto"}

        response = await self._client.messages.create(**kwargs)
        return self._parse_response(response)

    async def follow_up(
        self,
        system_prompt: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> LLMResponse:
        kwargs: dict[str, Any] = {
            "model": self._model,
            "max_tokens": self._max_tokens,
            "system": system_prompt,
            "messages": messages,
            "temperature": 0.5,
        }
        if tools:
            kwargs["tools"] = tools
            kwargs["tool_choice"] = {"type": "auto"}

        response = await self._client.messages.create(**kwargs)
        return self._parse_response(response)

    def _parse_response(self, response: Any) -> LLMResponse:
        from app.core.planner import _from_api_name

        text_parts: list[str] = []
        tool_calls: list[ToolCall] = []

        for block in response.content:
            if block.type == "text":
                text_parts.append(block.text)
            elif block.type == "tool_use":
                tool_calls.append(
                    ToolCall(
                        id=block.id,
                        name=_from_api_name(block.name),
                        arguments=block.input,  # already a dict
                    )
                )

        text = "\n".join(text_parts) if text_parts else None

        log.debug(
            "llm.anthropic.response",
            content=text[:200] if text else None,
            tool_calls=len(tool_calls),
            stop_reason=response.stop_reason,
        )
        return LLMResponse(text=text, tool_calls=tool_calls, raw=response)


# ---------------------------------------------------------------------------
# OpenAI implementation
# ---------------------------------------------------------------------------

class OpenAILLMClient(BaseLLMClient):
    def __init__(self) -> None:
        from openai import AsyncOpenAI

        self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        self._model = settings.openai_model

    async def chat(
        self,
        system_prompt: str,
        user_message: str,
        tools: list[dict[str, Any]] | None = None,
        messages: list[dict[str, Any]] | None = None,
    ) -> LLMResponse:
        msgs: list[dict[str, Any]] = [{"role": "system", "content": system_prompt}]
        if messages:
            msgs.extend(messages)
        msgs.append({"role": "user", "content": user_message})

        kwargs: dict[str, Any] = {
            "model": self._model,
            "messages": msgs,
            "temperature": 0.3,
        }
        if tools:
            kwargs["tools"] = tools
            kwargs["tool_choice"] = "auto"

        response = await self._client.chat.completions.create(**kwargs)
        return self._parse_response(response.choices[0].message)

    async def follow_up(
        self,
        system_prompt: str,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
    ) -> LLMResponse:
        # Prepend system prompt if not already in messages
        msgs = messages
        if not msgs or msgs[0].get("role") != "system":
            msgs = [{"role": "system", "content": system_prompt}, *msgs]

        kwargs: dict[str, Any] = {
            "model": self._model,
            "messages": msgs,
            "temperature": 0.5,
        }
        if tools:
            kwargs["tools"] = tools

        response = await self._client.chat.completions.create(**kwargs)
        return self._parse_response(response.choices[0].message)

    def _parse_response(self, msg: Any) -> LLMResponse:
        from app.core.planner import _from_api_name

        tool_calls: list[ToolCall] = []
        if msg.tool_calls:
            for tc in msg.tool_calls:
                tool_calls.append(
                    ToolCall(
                        id=tc.id,
                        name=_from_api_name(tc.function.name),
                        arguments=json.loads(tc.function.arguments),
                    )
                )

        log.debug(
            "llm.openai.response",
            content=msg.content[:200] if msg.content else None,
            tool_calls=len(tool_calls),
        )
        return LLMResponse(text=msg.content, tool_calls=tool_calls, raw=msg)


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

def create_llm_client() -> BaseLLMClient:
    """Create an LLM client based on the configured provider."""
    if settings.llm_provider == "anthropic":
        return AnthropicLLMClient()
    return OpenAILLMClient()
