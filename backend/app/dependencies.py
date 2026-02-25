from __future__ import annotations

import uuid
from datetime import UTC
from typing import Annotated

from cryptography.fernet import Fernet
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import get_db
from app.models.user import User

bearer_scheme = HTTPBearer()


def get_fernet() -> Fernet:
    if not settings.fernet_key:
        raise RuntimeError("FERNET_KEY is not configured")
    return Fernet(settings.fernet_key.encode())


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(bearer_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    token = credentials.credentials
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token payload")
    except JWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Could not validate token")

    result = await db.execute(select(User).where(User.id == uuid.UUID(user_id)))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found")
    return user


def create_access_token(user_id: str) -> str:
    from datetime import datetime, timedelta

    expire = datetime.now(UTC) + timedelta(minutes=settings.jwt_expire_minutes)
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
