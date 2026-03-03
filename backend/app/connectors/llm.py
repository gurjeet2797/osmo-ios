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
    stop_reason: str | None = None  # "end_turn", "max_tokens", "stop", "length", etc.


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
        image_data: str | None = None,
    ) -> LLMResponse:
        """Send a message (with optional history and image) and return a unified response."""

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
        import httpx

        self._client = AsyncAnthropic(
            api_key=settings.anthropic_api_key,
            timeout=httpx.Timeout(60.0, connect=10.0),
        )
        self._model = settings.anthropic_model
        self._max_tokens = settings.anthropic_max_tokens

    async def chat(
        self,
        system_prompt: str,
        user_message: str,
        tools: list[dict[str, Any]] | None = None,
        messages: list[dict[str, Any]] | None = None,
        image_data: str | None = None,
    ) -> LLMResponse:
        # Build message list: optional history + new user message
        msgs: list[dict[str, Any]] = list(messages or [])
        if image_data:
            msgs.append({"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": image_data}},
                {"type": "text", "text": user_message},
            ]})
        else:
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
        result = self._parse_response(response)

        # Continuation: if truncated text (no tool calls), ask LLM to finish (1 attempt)
        if result.stop_reason == "max_tokens" and not result.tool_calls and result.text:
            log.info("llm.anthropic.continuation", partial_len=len(result.text))
            msgs.append({"role": "assistant", "content": result.text})
            msgs.append({"role": "user", "content": "Please continue from where you left off."})
            kwargs["messages"] = msgs
            cont_response = await self._client.messages.create(**kwargs)
            cont_result = self._parse_response(cont_response)
            if cont_result.text:
                result.text = result.text + cont_result.text
            result.stop_reason = cont_result.stop_reason
            result.raw = cont_response

        return result

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
        return LLMResponse(
            text=text, tool_calls=tool_calls, raw=response,
            stop_reason=response.stop_reason,
        )


# ---------------------------------------------------------------------------
# OpenAI implementation
# ---------------------------------------------------------------------------

class OpenAILLMClient(BaseLLMClient):
    def __init__(self) -> None:
        from openai import AsyncOpenAI
        import httpx

        self._client = AsyncOpenAI(
            api_key=settings.openai_api_key,
            timeout=httpx.Timeout(60.0, connect=10.0),
        )
        self._model = settings.openai_model

    async def chat(
        self,
        system_prompt: str,
        user_message: str,
        tools: list[dict[str, Any]] | None = None,
        messages: list[dict[str, Any]] | None = None,
        image_data: str | None = None,
    ) -> LLMResponse:
        msgs: list[dict[str, Any]] = [{"role": "system", "content": system_prompt}]
        if messages:
            msgs.extend(messages)
        if image_data:
            msgs.append({"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_data}"}},
                {"type": "text", "text": user_message},
            ]})
        else:
            msgs.append({"role": "user", "content": user_message})

        kwargs: dict[str, Any] = {
            "model": self._model,
            "messages": msgs,
            "temperature": 0.3,
            "max_tokens": 2000,
        }
        if tools:
            kwargs["tools"] = tools
            kwargs["tool_choice"] = "auto"

        response = await self._client.chat.completions.create(**kwargs)
        choice = response.choices[0]
        result = self._parse_response(choice.message)
        result.stop_reason = choice.finish_reason

        # Continuation: if truncated text (no tool calls), ask LLM to finish (1 attempt)
        if result.stop_reason == "length" and not result.tool_calls and result.text:
            log.info("llm.openai.continuation", partial_len=len(result.text))
            msgs.append({"role": "assistant", "content": result.text})
            msgs.append({"role": "user", "content": "Please continue from where you left off."})
            kwargs["messages"] = msgs
            cont_response = await self._client.chat.completions.create(**kwargs)
            cont_choice = cont_response.choices[0]
            cont_result = self._parse_response(cont_choice.message)
            if cont_result.text:
                result.text = result.text + cont_result.text
            result.stop_reason = cont_choice.finish_reason
            result.raw = cont_choice.message

        return result

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
            "max_tokens": 2000,
        }
        if tools:
            kwargs["tools"] = tools

        response = await self._client.chat.completions.create(**kwargs)
        choice = response.choices[0]
        result = self._parse_response(choice.message)
        result.stop_reason = choice.finish_reason
        return result

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

_llm_client: BaseLLMClient | None = None


def create_llm_client() -> BaseLLMClient:
    """Return a singleton LLM client based on the configured provider."""
    global _llm_client
    if _llm_client is None:
        if settings.llm_provider == "anthropic":
            _llm_client = AnthropicLLMClient()
        else:
            _llm_client = OpenAILLMClient()
    return _llm_client
