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


def _period_start(sub: Subscription | None) -> datetime:
    """Credits belong to the subscription period that paid for them (30 days from
    the pay date), so usage is counted from `started_at` -- not the calendar
    month. Without a subscription fall back to the calendar month."""
    if sub is not None:
        return sub.started_at
    now = datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def credits_used(db: Session, user: User, sub: Subscription | None = None) -> int:
    """Edits charged in the current period. One Download row == one credit."""
    return db.scalar(
        select(func.count()).select_from(Download).where(
            Download.user_id == user.id, Download.created_at >= _period_start(sub)
        )
    ) or 0


def credits_left(db: Session, user: User, sub: Subscription | None) -> int | None:
    """Remaining credits this period; None = unlimited plan (or no plan)."""
    if sub is None or sub.plan.export_limit is None:
        return None
    return max(0, sub.plan.export_limit - credits_used(db, user, sub))


def paid_edit(db: Session, user: User, clip: Clip, sub: Subscription | None) -> Download | None:
    """The Download row that already paid for this clip in the current period.
    A clip is charged ONCE: reopening a draft never costs a second credit."""
    return db.scalar(
        select(Download)
        .where(
            Download.user_id == user.id,
            Download.clip_id == clip.id,
            Download.created_at >= _period_start(sub),
        )
        .order_by(Download.created_at.desc())
    )


def assert_can_export(db: Session, user: User, clip: Clip) -> Download | None:
    """Gate edits/exports: Pro clips need an active subscription; enforce the
    period quota. Returns the existing paid row when this clip was already
    charged this period (callers must NOT charge again), else None."""
    sub = current_subscription(db, user)

    if clip.access == Access.pro and sub is None:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            detail={"code": "subscription_required", "message": "Subscribe to export Pro clips."},
        )

    paid = paid_edit(db, user, clip, sub)
    if paid is not None:
        return paid

    if sub is not None and sub.plan.export_limit is not None:
        if credits_used(db, user, sub) >= sub.plan.export_limit:
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                detail={
                    "code": "quota_exceeded",
                    "message": f"No edit credits left in this period ({sub.plan.export_limit} used).",
                },
            )
    return None
