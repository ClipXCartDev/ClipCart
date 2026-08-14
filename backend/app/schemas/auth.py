"""Pydantic request/response schemas for auth + identity."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class DeviceInfo(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    os: str | None = None
    app_version: str | None = None


class RegisterIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    device: DeviceInfo | None = None


class LoginIn(BaseModel):
    email: EmailStr
    password: str
    device: DeviceInfo | None = None


class GoogleIn(BaseModel):
    id_token: str
    device: DeviceInfo | None = None


class RefreshIn(BaseModel):
    refresh_token: str


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    email: EmailStr
    role: str
    is_active: bool
    created_at: datetime


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    device_id: str
    os: str | None
    app_version: str | None
    ip: str | None
    country: str | None
    last_login: datetime
    last_active: datetime


class AuthOut(BaseModel):
    user: UserOut
    tokens: TokenOut
