"""Auth & identity endpoints: register, login, Google, refresh, me, devices."""
from __future__ import annotations

import uuid

import jwt
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.security import REFRESH, create_access_token, create_refresh_token, decode_token, hash_password, verify_password
from app.db.session import get_db
from app.models import Device, RefreshToken, Role, User
from app.schemas.auth import (
    AuthOut,
    DeviceOut,
    GoogleIn,
    LoginIn,
    RefreshIn,
    RegisterIn,
    TokenOut,
    UserOut,
)
from app.services import google as google_service
from app.services.auth import bind_device, issue_tokens, revoke_refresh

router = APIRouter(prefix="/auth", tags=["auth"])


def _client_ip(request: Request) -> str | None:
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else None


@router.post("/register", response_model=AuthOut, status_code=status.HTTP_201_CREATED)
def register(body: RegisterIn, request: Request, db: Session = Depends(get_db)) -> AuthOut:
    if db.scalar(select(User).where(User.email == body.email)):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Email already registered")

    user = User(
        name=body.name,
        email=body.email,
        password_hash=hash_password(body.password),
        role=Role.customer,
    )
    db.add(user)
    # Bind the device BEFORE committing the user so a device-limit 409 rolls the
    # new user back instead of leaving an orphan account that can't log in.
    db.flush()  # assign user.id without committing
    try:
        bind_device(db, user, body.device, _client_ip(request))
    except HTTPException:
        db.rollback()
        raise
    db.refresh(user)

    tokens = issue_tokens(db, user)
    return AuthOut(user=UserOut.model_validate(user), tokens=tokens)


@router.post("/login", response_model=AuthOut)
def login(body: LoginIn, request: Request, db: Session = Depends(get_db)) -> AuthOut:
    user = db.scalar(select(User).where(User.email == body.email))
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Account disabled")

    bind_device(db, user, body.device, _client_ip(request))
    tokens = issue_tokens(db, user)
    return AuthOut(user=UserOut.model_validate(user), tokens=tokens)


@router.post("/google", response_model=AuthOut)
def google_login(body: GoogleIn, request: Request, db: Session = Depends(get_db)) -> AuthOut:
    try:
        identity = google_service.verify_google_token(body.id_token)
    except google_service.GoogleAuthError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid Google token")

    user = db.scalar(select(User).where(User.google_sub == identity.sub))
    if not user:
        # Link by email if the account already exists, else create a new customer.
        user = db.scalar(select(User).where(User.email == identity.email))
        if user:
            user.google_sub = identity.sub
        else:
            user = User(
                name=identity.name,
                email=identity.email,
                google_sub=identity.sub,
                role=Role.customer,
            )
            db.add(user)
        db.commit()
        db.refresh(user)

    bind_device(db, user, body.device, _client_ip(request))
    tokens = issue_tokens(db, user)
    return AuthOut(user=UserOut.model_validate(user), tokens=tokens)


@router.post("/refresh", response_model=TokenOut)
def refresh(body: RefreshIn, db: Session = Depends(get_db)) -> TokenOut:
    invalid = HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
    try:
        payload = decode_token(body.refresh_token)
    except jwt.PyJWTError:
        raise invalid
    if payload.get("type") != REFRESH:
        raise invalid

    row = db.scalar(select(RefreshToken).where(RefreshToken.jti == payload.get("jti")))
    if not row or row.revoked:
        raise invalid

    try:
        user_id = uuid.UUID(payload["sub"])
    except (KeyError, ValueError):
        raise invalid
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise invalid

    # Rotate: revoke old jti, issue a fresh pair.
    revoke_refresh(db, row.jti)
    return issue_tokens(db, user)


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)) -> UserOut:
    return UserOut.model_validate(user)


@router.get("/devices", response_model=list[DeviceOut])
def list_devices(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> list[DeviceOut]:
    rows = db.scalars(select(Device).where(Device.user_id == user.id)).all()
    return [DeviceOut.model_validate(d) for d in rows]


@router.delete("/devices/{device_id}")
def remove_device(
    device_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.scalar(select(Device).where(Device.id == device_id, Device.user_id == user.id))
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Device not found")
    db.delete(row)
    db.commit()
    return {"deleted": True}
