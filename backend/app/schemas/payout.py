"""Payout schemas."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class EarningsOut(BaseModel):
    downloads: int
    rate: float
    earned: float
    pending: float
    paid: float
    available: float


class PayoutCreate(BaseModel):
    amount: float = Field(gt=0)


class PayoutOut(BaseModel):
    id: uuid.UUID
    editor_id: uuid.UUID
    editor_name: str | None = None
    amount: float
    status: str
    note: str | None = None
    created_at: datetime
    paid_at: datetime | None = None
