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


def activate_from_payment(
    db: Session,
    payment: Payment,
    paid_amount: object = None,
    paid_currency: str | None = None,
) -> Subscription:
    """Mark payment paid and create/extend the user's subscription (manual renewal).

    Security (C3): when the webhook reports a paid amount/currency, they MUST match the
    stored payment before we activate — otherwise an attacker could underpay and still
    unlock a subscription. Also idempotent: a payment already marked paid is never
    re-activated (replay protection).
    """
    now = datetime.now(timezone.utc)

    # Idempotency / replay guard — never re-activate an already-paid payment.
    if payment.status == PaymentStatus.paid:
        existing = db.scalar(
            select(Subscription).where(
                Subscription.user_id == payment.user_id,
                Subscription.status == SubStatus.active,
            ).order_by(Subscription.expires_at.desc())
        )
        if existing:
            return existing

    # Verify the webhook-reported amount/currency equals the stored payment (C3).
    if paid_amount is not None:
        from decimal import Decimal, InvalidOperation
        try:
            reported = Decimal(str(paid_amount))
            expected = Decimal(str(payment.amount))
        except (InvalidOperation, ValueError):
            reported = expected = None
        if reported is None or reported != expected:
            payment.status = PaymentStatus.failed
            db.commit()
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail={"code": "amount_mismatch", "message": "Paid amount does not match order."},
            )
    if paid_currency is not None and str(paid_currency).upper() != str(payment.currency).upper():
        payment.status = PaymentStatus.failed
        db.commit()
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={"code": "currency_mismatch", "message": "Paid currency does not match order."},
        )

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
