from __future__ import annotations

import hashlib
import json
import os
import base64
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from google_auth_oauthlib.flow import Flow
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.dependencies import create_access_token, get_fernet
from app.models.user import User

router = APIRouter()

# In-memory PKCE verifier store keyed by OAuth state parameter
_pkce_store: dict[str, str] = {}

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
    if mobile:
        flow.redirect_uri = settings.google_redirect_uri.replace("/callback", "/callback/mobile")

    code_verifier, code_challenge = _generate_pkce()

    auth_url, state = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent",
        code_challenge=code_challenge,
        code_challenge_method="S256",
    )

    _pkce_store[state] = code_verifier

    return {"auth_url": auth_url}


@router.get("/google/callback")
async def google_callback(
    code: Annotated[str, Query()],
    state: Annotated[str, Query()],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    flow = _build_flow()
    code_verifier = _pkce_store.pop(state, None)
    flow.fetch_token(code=code, code_verifier=code_verifier)
    credentials = flow.credentials

    import httpx

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "https://www.googleapis.com/oauth2/v2/userinfo",
            headers={"Authorization": f"Bearer {credentials.token}"},
        )
        if resp.status_code != 200:
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Failed to fetch user info")
        user_info = resp.json()

    email = user_info.get("email")
    if not email:
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
        user = User(email=email, google_tokens_encrypted=encrypted_tokens)
        db.add(user)
    else:
        user.google_tokens_encrypted = encrypted_tokens

    await db.commit()
    await db.refresh(user)

    access_token = create_access_token(str(user.id))
    return {"access_token": access_token, "token_type": "bearer", "email": email}


@router.get("/google/callback/mobile")
async def google_callback_mobile(
    code: Annotated[str, Query()],
    state: Annotated[str, Query()],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Mobile OAuth callback — redirects to osmo:// custom URL scheme."""
    flow = _build_flow()
    flow.redirect_uri = settings.google_redirect_uri.replace("/callback", "/callback/mobile")
    code_verifier = _pkce_store.pop(state, None)
    flow.fetch_token(code=code, code_verifier=code_verifier)
    credentials = flow.credentials

    import httpx

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "https://www.googleapis.com/oauth2/v2/userinfo",
            headers={"Authorization": f"Bearer {credentials.token}"},
        )
        if resp.status_code != 200:
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Failed to fetch user info")
        user_info = resp.json()

    email = user_info.get("email")
    if not email:
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
        user = User(email=email, google_tokens_encrypted=encrypted_tokens)
        db.add(user)
    else:
        user.google_tokens_encrypted = encrypted_tokens

    await db.commit()
    await db.refresh(user)

    access_token = create_access_token(str(user.id))

    from urllib.parse import urlencode
    from fastapi.responses import RedirectResponse

    params = urlencode({"token": access_token, "email": email})
    return RedirectResponse(url=f"osmo://auth/callback?{params}")
