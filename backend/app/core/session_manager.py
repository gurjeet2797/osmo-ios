from __future__ import annotations

import json
from typing import Any

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.chat_session import ChatSession

log = structlog.get_logger()


class SessionManager:
    """Manages per-user conversation sessions stored in the database."""

    def __init__(self, db: AsyncSession, user_id: str) -> None:
        self._db = db
        self._user_id = user_id
        self._max_messages = settings.session_max_messages

    async def load(self) -> list[dict[str, Any]]:
        """Load the user's session messages, or return [] if none exists."""
        result = await self._db.execute(
            select(ChatSession).where(ChatSession.user_id == self._user_id)
        )
        session = result.scalar_one_or_none()
        if session is None:
            return []
        return session.messages or []

    async def save(self, messages: list[dict[str, Any]]) -> None:
        """Upsert the user's session, trimming to max messages."""
        trimmed = self._trim(messages)

        result = await self._db.execute(
            select(ChatSession).where(ChatSession.user_id == self._user_id)
        )
        session = result.scalar_one_or_none()

        if session is None:
            session = ChatSession(
                user_id=self._user_id,
                messages=trimmed,
                message_count=len(trimmed),
            )
            self._db.add(session)
        else:
            session.messages = trimmed
            session.message_count = len(trimmed)

        await self._db.commit()
        log.debug("session.saved", user_id=self._user_id, message_count=len(trimmed))

    async def clear(self) -> None:
        """Delete the user's session."""
        result = await self._db.execute(
            select(ChatSession).where(ChatSession.user_id == self._user_id)
        )
        session = result.scalar_one_or_none()
        if session is not None:
            await self._db.delete(session)
            await self._db.commit()
        log.info("session.cleared", user_id=self._user_id)

    def _trim(self, messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Keep last N messages, ensuring the first message is a plain user text.

        Anthropic requires the first message to be role=user with text content,
        not tool_result blocks or assistant messages.
        """
        if len(messages) <= self._max_messages:
            return messages

        trimmed = messages[-self._max_messages :]

        # Walk forward to find a plain user text message
        start = 0
        for i, msg in enumerate(trimmed):
            if msg.get("role") == "user" and self._is_plain_text(msg):
                start = i
                break
        else:
            # No plain user message found — return only the last few messages
            # This shouldn't happen in practice
            return trimmed[-4:]

        return trimmed[start:]

    @staticmethod
    def _is_plain_text(msg: dict[str, Any]) -> bool:
        """Check if a message is plain text (not tool_result blocks)."""
        content = msg.get("content")
        if isinstance(content, str):
            return True
        if isinstance(content, list):
            return all(
                isinstance(b, dict) and b.get("type") == "text" for b in content
            )
        return False

    # ---- Anthropic format helpers ----

    @staticmethod
    def append_user_message(
        messages: list[dict[str, Any]], content: str
    ) -> list[dict[str, Any]]:
        """Append a plain text user message (Anthropic format)."""
        messages.append({"role": "user", "content": content})
        return messages

    @staticmethod
    def append_assistant_response(
        messages: list[dict[str, Any]], response: Any
    ) -> list[dict[str, Any]]:
        """Serialize an Anthropic response's content blocks into session format."""
        content_blocks: list[dict[str, Any]] = []
        for block in response.raw.content:
            if block.type == "text":
                content_blocks.append({"type": "text", "text": block.text})
            elif block.type == "tool_use":
                content_blocks.append(
                    {
                        "type": "tool_use",
                        "id": block.id,
                        "name": block.name,
                        "input": block.input,
                    }
                )
        messages.append({"role": "assistant", "content": content_blocks})
        return messages

    @staticmethod
    def append_tool_results(
        messages: list[dict[str, Any]],
        results: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        """Append tool_result blocks as a user message (Anthropic format)."""
        messages.append({"role": "user", "content": results})
        return messages

    # ---- OpenAI format helpers ----

    @staticmethod
    def append_openai_user_message(
        messages: list[dict[str, Any]], content: str
    ) -> list[dict[str, Any]]:
        """Append a plain text user message (OpenAI format)."""
        messages.append({"role": "user", "content": content})
        return messages

    @staticmethod
    def append_openai_assistant_response(
        messages: list[dict[str, Any]], response: Any
    ) -> list[dict[str, Any]]:
        """Serialize an OpenAI response message into session format."""
        msg: dict[str, Any] = {
            "role": "assistant",
            "content": response.text,
        }
        if response.tool_calls:
            from app.core.planner import _to_api_name
            msg["tool_calls"] = [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {
                        "name": _to_api_name(tc.name),
                        "arguments": json.dumps(tc.arguments),
                    },
                }
                for tc in response.tool_calls
            ]
        messages.append(msg)
        return messages

    @staticmethod
    def append_openai_tool_results(
        messages: list[dict[str, Any]],
        tool_calls: list,
        step_results: list,
    ) -> list[dict[str, Any]]:
        """Append tool result messages (OpenAI format — one per tool call)."""
        for tc, sr in zip(tool_calls, step_results):
            if sr.success:
                content = json.dumps(sr.result) if sr.result else '{"status": "ok"}'
            else:
                content = json.dumps({"error": sr.error or "unknown error"})
            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": content,
            })
        return messages
