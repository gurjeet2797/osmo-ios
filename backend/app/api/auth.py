from __future__ import annotations

import hashlib
import json
import os
import base64
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, status
from google_auth_oauthlib.flow import Flow
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db, get_redis
from app.dependencies import create_access_token, get_fernet
from app.models.user import User

log = structlog.get_logger()

router = APIRouter()

_PKCE_PREFIX = "pkce:"
_PKCE_TTL = 600  # 10 minutes


async def _store_pkce(state: str, verifier: str, *, mobile: bool = False) -> None:
    r = await get_redis()
    payload = json.dumps({"verifier": verifier, "mobile": mobile})
    await r.set(f"{_PKCE_PREFIX}{state}", payload, ex=_PKCE_TTL)


async def _pop_pkce(state: str) -> tuple[str, bool] | None:
    """Return (verifier, mobile) or None if expired/missing."""
    r = await get_redis()
    key = f"{_PKCE_PREFIX}{state}"
    async with r.pipeline(transaction=True) as pipe:
        pipe.get(key)
        pipe.delete(key)
        result = await pipe.execute()
    raw = result[0]
    if raw is None:
        return None
    data = json.loads(raw)
    return data["verifier"], data["mobile"]

GOOGLE_SCOPES = [
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/gmail.readonly",
]


def _build_flow() -> Flow:
    client_config = {
        "web": {
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [settings.google_redirect_uri],
        }
    }
    flow = Flow.from_client_config(client_config, scopes=GOOGLE_SCOPES)
    flow.redirect_uri = settings.google_redirect_uri
    return flow


def _generate_pkce() -> tuple[str, str]:
    """Generate PKCE code_verifier and code_challenge."""
    code_verifier = base64.urlsafe_b64encode(os.urandom(40)).rstrip(b"=").decode()
    digest = hashlib.sha256(code_verifier.encode()).digest()
    code_challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode()
    return code_verifier, code_challenge


@router.post("/google")
async def start_google_oauth(mobile: bool = True):
    flow = _build_flow()

    log.info(
        "start_google_oauth",
        redirect_uri=flow.redirect_uri,
        mobile=mobile,
    )

    code_verifier, code_challenge = _generate_pkce()

    auth_url, state = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent",
        code_challenge=code_challenge,
        code_challenge_method="S256",
    )

    await _store_pkce(state, code_verifier, mobile=mobile)

    return {"auth_url": auth_url}


@router.get("/google/callback")
async def google_callback(
    code: Annotated[str, Query()],
    state: Annotated[str, Query()],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    from urllib.parse import urlencode
    from fastapi.responses import RedirectResponse

    flow = _build_flow()
    pkce_result = await _pop_pkce(state)
    if pkce_result is None:
        log.warning("google_callback: PKCE verifier not found", state=state)
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "OAuth session expired or server restarted. Please sign in again.",
        )

    code_verifier, is_mobile = pkce_result

    try:
        flow.fetch_token(code=code, code_verifier=code_verifier)
    except Exception as exc:
        log.error("google_callback: token exchange failed", error=str(exc))
        if is_mobile:
            params = urlencode({"error": f"Sign-in failed: {exc}"})
            return RedirectResponse(url=f"osmo://auth/callback?{params}")
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"Google token exchange failed: {exc}",
        )
    credentials = flow.credentials

    import httpx

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "https://www.googleapis.com/oauth2/v2/userinfo",
            headers={"Authorization": f"Bearer {credentials.token}"},
        )
        if resp.status_code != 200:
            if is_mobile:
                params = urlencode({"error": "Failed to fetch user info from Google."})
                return RedirectResponse(url=f"osmo://auth/callback?{params}")
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Failed to fetch user info")
        user_info = resp.json()

    email = user_info.get("email")
    google_name = user_info.get("name")
    if not email:
        if is_mobile:
            params = urlencode({"error": "No email in Google response."})
            return RedirectResponse(url=f"osmo://auth/callback?{params}")
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "No email in Google response")

    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    fernet = get_fernet()
    tokens_json = json.dumps(
        {
            "token": credentials.token,
            "refresh_token": credentials.refresh_token,
            "token_uri": credentials.token_uri,
            "client_id": credentials.client_id,
            "client_secret": credentials.client_secret,
            "scopes": list(credentials.scopes or []),
        }
    )
    encrypted_tokens = fernet.encrypt(tokens_json.encode()).decode()

    if user is None:
        user = User(email=email, name=google_name, google_tokens_encrypted=encrypted_tokens)
        db.add(user)
    else:
        user.google_tokens_encrypted = encrypted_tokens
        if google_name and not user.name:
            user.name = google_name

    await db.commit()
    await db.refresh(user)

    access_token = create_access_token(str(user.id))

    if is_mobile:
        params = urlencode({"token": access_token, "email": email, "name": google_name or ""})
        return RedirectResponse(url=f"osmo://auth/callback?{params}")

    return {"access_token": access_token, "token_type": "bearer", "email": email}
