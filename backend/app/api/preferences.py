from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.preference_manager import PreferenceManager
from app.db.session import get_db
from app.dependencies import get_current_user
from app.models.user import User

router = APIRouter()


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
    mgr = PreferenceManager(db, str(user.id))
    for key, value in body.items():
        await mgr.set(key, value, source="user_settings")
    return await mgr.get_all()
