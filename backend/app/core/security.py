"""Password hashing (Argon2) and JWT access/refresh tokens (decisions §6.1)."""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError

from app.core.config import settings

_ph = PasswordHasher()

ACCESS = "access"
REFRESH = "refresh"


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except (VerifyMismatchError, VerificationError):
        return False


def _create_token(
    subject: str, token_type: str, expires: timedelta, did: str | None = None
) -> tuple[str, str, datetime]:
    now = datetime.now(timezone.utc)
    exp = now + expires
    jti = str(uuid.uuid4())
    payload = {"sub": subject, "type": token_type, "iat": now, "exp": exp, "jti": jti}
    if did is not None:
        payload["did"] = did
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    return token, jti, exp


def create_access_token(subject: str, did: str | None = None) -> tuple[str, str, datetime]:
    return _create_token(
        subject, ACCESS, timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES), did
    )


def create_refresh_token(subject: str, did: str | None = None) -> tuple[str, str, datetime]:
    return _create_token(
        subject, REFRESH, timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS), did
    )


def decode_token(token: str) -> dict:
    """Raises jwt.PyJWTError on invalid/expired token."""
    return jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
