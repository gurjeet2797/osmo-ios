from __future__ import annotations

import re
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.preference_manager import PreferenceManager
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.user import User

router = APIRouter()

_ALLOWED_KEY_PATTERN = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
_MAX_VALUE_LENGTH = 10_000  # 10KB per value
_MAX_KEYS = 50


@router.get("")
async def get_preferences(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, str]:
    mgr = PreferenceManager(db, str(user.id))
    return await mgr.get_all()


@router.put("")
async def set_preferences(
    body: dict[str, str],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, str]:
    if len(body) > _MAX_KEYS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Too many keys (max {_MAX_KEYS})")
    for key, value in body.items():
        if not _ALLOWED_KEY_PATTERN.match(key):
            raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Invalid preference key: {key}")
        if len(value) > _MAX_VALUE_LENGTH:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Value too long for key: {key}")
    mgr = PreferenceManager(db, str(user.id))
    for key, value in body.items():
        await mgr.set(key, value, source="user_settings")
    return await mgr.get_all()
