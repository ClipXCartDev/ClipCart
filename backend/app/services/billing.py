"""Billing domain logic: subscription activation + export access/quota gate."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import (
    Access,
    Clip,
    Download,
    Payment,
    PaymentStatus,
    Subscription,
    SubStatus,
    User,
)


def current_subscription(db: Session, user: User) -> Subscription | None:
    now = datetime.now(timezone.utc)
    return db.scalar(
        select(Subscription)
        .where(
            Subscription.user_id == user.id,
            Subscription.status == SubStatus.active,
            Subscription.expires_at > now,
        )
        .order_by(Subscription.expires_at.desc())
    )


def activate_from_payment(db: Session, payment: Payment) -> Subscription:
    """Mark payment paid and create/extend the user's subscription (manual renewal)."""
    now = datetime.now(timezone.utc)
    payment.status = PaymentStatus.paid
    payment.paid_at = now

    # Fetch active sub directly (avoid needing the User object).
    active = db.scalar(
        select(Subscription).where(
            Subscription.user_id == payment.user_id,
            Subscription.status == SubStatus.active,
            Subscription.expires_at > now,
        ).order_by(Subscription.expires_at.desc())
    )
    base = active.expires_at if active else now
    if base < now:
        base = now

    # expire any current active subs, then create the renewed one (keeps history).
    for s in db.scalars(select(Subscription).where(
        Subscription.user_id == payment.user_id, Subscription.status == SubStatus.active
    )).all():
        s.status = SubStatus.expired

    sub = Subscription(
        user_id=payment.user_id,
        plan_id=payment.plan_id,
        status=SubStatus.active,
        started_at=now,
        expires_at=base + timedelta(days=settings.SUBSCRIPTION_DAYS),
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return sub


def _exports_this_month(db: Session, user: User) -> int:
    now = datetime.now(timezone.utc)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    return db.scalar(
        select(func.count()).select_from(Download).where(
            Download.user_id == user.id, Download.created_at >= start
        )
    ) or 0


def assert_can_export(db: Session, user: User, clip: Clip) -> None:
    """Gate exports: Pro clips need an active subscription; enforce monthly quota."""
    sub = current_subscription(db, user)

    if clip.access == Access.pro and sub is None:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            detail={"code": "subscription_required", "message": "Subscribe to export Pro clips."},
        )

    if sub is not None and sub.plan.export_limit is not None:
        used = _exports_this_month(db, user)
        if used >= sub.plan.export_limit:
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                detail={
                    "code": "quota_exceeded",
                    "message": f"Monthly export limit ({sub.plan.export_limit}) reached.",
                },
            )
