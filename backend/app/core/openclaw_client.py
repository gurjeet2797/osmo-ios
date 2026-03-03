"""
openclaw_client.py — Async HTTP client for the OpenClaw AI gateway.

Osmo delegates complex, multi-step, or memory-requiring tasks to an OpenClaw
instance running as a sidecar. This client handles all communication with it.
If OpenClaw is unreachable, all methods fail gracefully so the main Osmo flow
is never broken.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

_TIMEOUT = httpx.Timeout(30.0, connect=5.0)


class OpenClawClient:
    """Thin async wrapper around the OpenClaw gateway HTTP API."""

    def __init__(
        self,
        base_url: str | None = None,
        token: str | None = None,
    ) -> None:
        self.base_url = (base_url or settings.openclaw_url).rstrip("/")
        self.token = token or settings.openclaw_token
        self._headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }

    async def send_message(
        self,
        text: str,
        session_id: str = "osmo-default",
        context: dict[str, Any] | None = None,
    ) -> str | None:
        """
        Send a message to OpenClaw and return the text response.

        Uses the OpenResponses-compatible /v1/responses endpoint.
        Returns None if OpenClaw is disabled, unreachable, or returns an error.
        Callers should fall back to the local planner on None.
        """
        if not settings.openclaw_enabled:
            return None

        # Build the input with optional context prefix
        if context:
            context_str = "\n".join(f"{k}: {v}" for k, v in context.items())
            full_input = f"[Context]\n{context_str}\n\n[User request]\n{text}"
        else:
            full_input = text

        payload: dict[str, Any] = {
            "model": "openclaw",
            "input": full_input,
            "user": session_id,
        }

        try:
            async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
                resp = await client.post(
                    f"{self.base_url}/v1/responses",
                    headers=self._headers,
                    json=payload,
                )
                resp.raise_for_status()
                data = resp.json()
                # OpenResponses format: {output: [{content: [{text: "..."}]}]}
                for output_item in data.get("output", []):
                    for content_block in output_item.get("content", []):
                        if content_block.get("type") == "output_text":
                            return content_block["text"]
                return None

        except httpx.ConnectError:
            logger.warning("OpenClaw unreachable at %s — falling back to local planner", self.base_url)
        except httpx.TimeoutException:
            logger.warning("OpenClaw request timed out — falling back to local planner")
        except httpx.HTTPStatusError as exc:
            logger.warning("OpenClaw returned %s — falling back to local planner", exc.response.status_code)
        except Exception as exc:  # noqa: BLE001
            logger.warning("OpenClaw error: %s — falling back to local planner", exc)

        return None

    async def health_check(self) -> dict[str, Any]:
        """
        Ping the OpenClaw gateway and return a status dict.
        Always returns a dict; never raises.
        """
        if not settings.openclaw_enabled:
            return {"enabled": False, "reachable": False, "url": self.base_url}

        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(5.0)) as client:
                # Use the responses endpoint with a trivial ping to verify reachability
                resp = await client.post(
                    f"{self.base_url}/v1/responses",
                    headers=self._headers,
                    json={"model": "openclaw", "input": "ping", "max_output_tokens": 1},
                )
                return {
                    "enabled": True,
                    "reachable": resp.status_code < 500,
                    "status_code": resp.status_code,
                    "url": self.base_url,
                }
        except Exception as exc:  # noqa: BLE001
            return {
                "enabled": True,
                "reachable": False,
                "url": self.base_url,
                "error": str(exc),
            }


# Module-level singleton — import this in executor.py and briefing modules
openclaw_client = OpenClawClient()
