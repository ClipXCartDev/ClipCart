"""Billing schemas."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PlanOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    slug: str
    price_usd: float
    currency: str
    export_limit: int | None
    quality: str
    max_devices: int
    features: list
    is_active: bool


class PlanCreate(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    price_usd: float = 0
    export_limit: int | None = None
    quality: str = "1080p"
    max_devices: int = 2
    features: list[str] = []
    sort_order: int = 0


class PlanUpdate(BaseModel):
    name: str | None = None
    price_usd: float | None = None
    export_limit: int | None = None
    quality: str | None = None
    max_devices: int | None = None
    features: list[str] | None = None
    is_active: bool | None = None
    sort_order: int | None = None


class CheckoutIn(BaseModel):
    plan_id: uuid.UUID


class CheckoutOut(BaseModel):
    payment_id: uuid.UUID
    order_id: str
    checkout_url: str
    qr_content: str
    amount: str
    currency: str


class SubscriptionOut(BaseModel):
    id: uuid.UUID
    plan_name: str
    status: str
    started_at: datetime
    expires_at: datetime


class PaymentOut(BaseModel):
    id: uuid.UUID
    plan_name: str
    amount: float
    currency: str
    status: str
    provider_order_id: str | None
    created_at: datetime
    paid_at: datetime | None
