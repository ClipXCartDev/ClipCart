"""Shared API dependencies: current user + role guards."""
from __future__ import annotations

import uuid

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.security import ACCESS, decode_token
from app.db.session import get_db
from app.models import Role, User

_bearer = HTTPBearer(auto_error=True)


def get_current_user(
    cred: HTTPAuthorizationCredentials = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    creds_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(cred.credentials)
    except jwt.PyJWTError:
        raise creds_exc
    if payload.get("type") != ACCESS:
        raise creds_exc
    try:
        user_id = uuid.UUID(payload["sub"])
    except (KeyError, ValueError):
        raise creds_exc

    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise creds_exc
    return user


def require_role(*roles: Role):
    def _guard(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
        return user

    return _guard
