from __future__ import annotations

import json
from typing import Any

import structlog
from openai import AsyncOpenAI

from app.config import settings

log = structlog.get_logger()


class LLMClient:
    def __init__(self):
        self._client = AsyncOpenAI(api_key=settings.openai_api_key)
        self._model = settings.openai_model

    async def plan(
        self,
        system_prompt: str,
        user_message: str,
        tool_specs: list[dict[str, Any]],
    ) -> dict[str, Any]:
        """Call the LLM with structured output to produce an ActionPlan JSON.

        Uses response_format to enforce JSON output rather than function calling,
        since we want the LLM to produce the full ActionPlan structure directly.
        """
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ]

        response = await self._client.chat.completions.create(
            model=self._model,
            messages=messages,
            response_format={"type": "json_object"},
            temperature=0.1,
        )

        content = response.choices[0].message.content
        if not content:
            raise ValueError("LLM returned empty response")

        log.debug("llm.plan.raw_response", content=content[:500])
        return json.loads(content)

    async def plan_with_retry(
        self,
        system_prompt: str,
        user_message: str,
        tool_specs: list[dict[str, Any]],
        validation_error: str | None = None,
    ) -> dict[str, Any]:
        """Call plan(), and if Pydantic validation fails, retry once with the error."""
        if validation_error:
            user_message = (
                f"{user_message}\n\n"
                f"[SYSTEM: Your previous response failed validation with this error: "
                f"{validation_error}. Fix it and try again.]"
            )

        return await self.plan(system_prompt, user_message, tool_specs)
