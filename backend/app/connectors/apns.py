"""Lightweight APNs client using HTTP/2 via JWT authentication."""
from __future__ import annotations

import json
import time

import structlog

from app.config import settings

log = structlog.get_logger()


async def send_push_notification(
    device_token: str,
    title: str,
    body: str,
    *,
    badge: int | None = None,
    sound: str = "default",
    data: dict | None = None,
) -> bool:
    """Send a push notification via APNs.

    Returns True if sent successfully, False otherwise.
    Requires APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_PATH in settings.
    Falls back to no-op if APNs is not configured.
    """
    if not getattr(settings, "apns_key_path", ""):
        log.debug("apns.not_configured")
        return False

    try:
        import httpx
        import jwt as pyjwt

        # Build JWT token for APNs
        apns_token = _build_apns_jwt()
        if not apns_token:
            return False

        # Build payload
        alert = {"title": title, "body": body}
        aps: dict = {"alert": alert, "sound": sound}
        if badge is not None:
            aps["badge"] = badge
        payload: dict = {"aps": aps}
        if data:
            payload.update(data)

        # Determine environment
        if settings.environment == "production":
            apns_host = "https://api.push.apple.com"
        else:
            apns_host = "https://api.sandbox.push.apple.com"

        url = f"{apns_host}/3/device/{device_token}"
        headers = {
            "authorization": f"bearer {apns_token}",
            "apns-topic": getattr(settings, "apns_bundle_id", "com.gurjeet.osmo"),
            "apns-push-type": "alert",
            "apns-priority": "10",
        }

        async with httpx.AsyncClient(http2=True, timeout=10.0) as client:
            resp = await client.post(url, json=payload, headers=headers)

        if resp.status_code == 200:
            log.info("apns.sent", token=device_token[:8])
            return True
        else:
            log.warning("apns.failed", status=resp.status_code, body=resp.text[:200])
            return False

    except Exception:
        log.warning("apns.error", exc_info=True)
        return False


def _build_apns_jwt() -> str | None:
    """Build a JWT token for APNs authentication."""
    try:
        import jwt as pyjwt

        key_path = getattr(settings, "apns_key_path", "")
        key_id = getattr(settings, "apns_key_id", "")
        team_id = getattr(settings, "apns_team_id", "")

        if not all([key_path, key_id, team_id]):
            return None

        with open(key_path) as f:
            private_key = f.read()

        payload = {
            "iss": team_id,
            "iat": int(time.time()),
        }
        headers = {
            "alg": "ES256",
            "kid": key_id,
        }
        return pyjwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    except Exception:
        log.warning("apns.jwt_build_failed", exc_info=True)
        return None
