"""Auth domain logic: token issuance/rotation + device binding (max N devices)."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, create_refresh_token
from app.models import Device, RefreshToken, User
from app.schemas.auth import DeviceInfo, DeviceOut, TokenOut


def issue_tokens(db: Session, user: User, did: str | None = None) -> TokenOut:
    access, _, _ = create_access_token(str(user.id), did)
    refresh, jti, exp = create_refresh_token(str(user.id), did)
    db.add(RefreshToken(user_id=user.id, jti=jti, expires_at=exp))
    db.commit()
    return TokenOut(access_token=access, refresh_token=refresh)


def revoke_refresh(db: Session, jti: str) -> None:
    row = db.scalar(select(RefreshToken).where(RefreshToken.jti == jti))
    if row:
        row.revoked = True
        db.commit()


def bind_device(db: Session, user: User, info: DeviceInfo | None, ip: str | None) -> str | None:
    """Register/refresh the calling device. Enforces MAX_DEVICES (decisions §7.1).

    Returns the bound Device row id (str) so it can be embedded in the access
    token as a `did` claim, or None when no device info was supplied.
    """
    if info is None:
        return None

    now = datetime.now(timezone.utc)
    existing = db.scalar(
        select(Device).where(Device.user_id == user.id, Device.device_id == info.device_id)
    )
    if existing:
        existing.last_login = now
        existing.last_active = now
        if ip:
            existing.ip = ip
        db.commit()
        return str(existing.id)

    active = db.scalars(select(Device).where(Device.user_id == user.id)).all()
    if len(active) >= settings.MAX_DEVICES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "device_limit",
                "message": f"Max {settings.MAX_DEVICES} devices. Remove one or buy a slot.",
                "devices": [DeviceOut.model_validate(d).model_dump(mode="json") for d in active],
            },
        )

    device = Device(
        user_id=user.id,
        device_id=info.device_id,
        os=info.os,
        app_version=info.app_version,
        ip=ip,
    )
    db.add(device)
    db.commit()
    return str(device.id)
