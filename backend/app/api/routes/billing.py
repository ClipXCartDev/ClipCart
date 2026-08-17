"""Billing: plans, Binance Pay checkout, signed webhook, subscription, payment history."""
from __future__ import annotations

import json
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models import Payment, PaymentStatus, Plan, Subscription, User
from app.schemas.billing import (
    CheckoutIn,
    CheckoutOut,
    PaymentOut,
    PlanOut,
    SubscriptionOut,
)
from app.services import binance
from app.services.billing import activate_from_payment, current_subscription

router = APIRouter(prefix="/billing", tags=["billing"])


@router.get("/plans", response_model=list[PlanOut])
def list_plans(db: Session = Depends(get_db)) -> list[PlanOut]:
    rows = db.scalars(select(Plan).where(Plan.is_active == True).order_by(Plan.sort_order)).all()  # noqa: E712
    return [PlanOut.model_validate(p) for p in rows]


@router.post("/checkout", response_model=CheckoutOut)
def checkout(body: CheckoutIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> CheckoutOut:
    plan = db.get(Plan, body.plan_id)
    if not plan or not plan.is_active:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Plan not found")

    order_id = "cc-" + uuid.uuid4().hex
    payment = Payment(
        user_id=user.id,
        plan_id=plan.id,
        amount=plan.price_usd,
        currency=plan.currency,
        provider_order_id=order_id,
        status=PaymentStatus.created,
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)

    order = binance.create_order(order_id, plan.price_usd, plan.currency)
    return CheckoutOut(
        payment_id=payment.id,
        order_id=order_id,
        checkout_url=order["checkout_url"],
        qr_content=order["qr_content"],
        amount=str(plan.price_usd),
        currency=plan.currency,
    )


@router.post("/webhook")
async def webhook(request: Request, db: Session = Depends(get_db)) -> dict:
    """Binance Pay webhook — verify signature, then activate. Frontend never trusted (§2.4)."""
    body = (await request.body()).decode("utf-8")
    ts = request.headers.get("BinancePay-Timestamp", "")
    nonce = request.headers.get("BinancePay-Nonce", "")
    sig = request.headers.get("BinancePay-Signature", "")
    if not binance.verify_webhook_signature(ts, nonce, body, sig):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Bad signature")

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Bad body")

    biz_status = data.get("bizStatus")
    order_ref = None
    inner = data.get("data")
    if isinstance(inner, str):
        try:
            inner = json.loads(inner)
        except json.JSONDecodeError:
            inner = None
    if isinstance(inner, dict):
        order_ref = inner.get("merchantTradeNo")
    else:
        inner = {}
    order_ref = order_ref or data.get("merchantTradeNo")

    # Binance webhook data carries the settled amount/currency (totalFee/currency).
    paid_amount = inner.get("totalFee", inner.get("orderAmount", data.get("totalFee")))
    paid_currency = inner.get("currency", data.get("currency"))

    payment = db.scalar(select(Payment).where(Payment.provider_order_id == order_ref))
    if payment and payment.status != PaymentStatus.paid:
        payment.raw = data
        if biz_status == "PAY_SUCCESS":
            # Verifies amount/currency match + idempotent (C3); rejects underpayment.
            activate_from_payment(db, payment, paid_amount=paid_amount, paid_currency=paid_currency)
        elif biz_status in ("PAY_CLOSED", "PAY_EXPIRED"):
            payment.status = PaymentStatus.expired if biz_status == "PAY_EXPIRED" else PaymentStatus.failed
            db.commit()

    return {"returnCode": "SUCCESS", "returnMessage": None}


@router.get("/subscription", response_model=SubscriptionOut | None)
def my_subscription(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    sub = current_subscription(db, user)
    if not sub:
        return None
    return SubscriptionOut(
        id=sub.id, plan_name=sub.plan.name, status=sub.status.value,
        started_at=sub.started_at, expires_at=sub.expires_at,
    )


@router.get("/payments", response_model=list[PaymentOut])
def my_payments(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[PaymentOut]:
    rows = db.scalars(select(Payment).where(Payment.user_id == user.id).order_by(Payment.created_at.desc())).all()
    return [
        PaymentOut(
            id=p.id, plan_name=p.plan.name, amount=float(p.amount), currency=p.currency,
            status=p.status.value, provider_order_id=p.provider_order_id,
            created_at=p.created_at, paid_at=p.paid_at,
        )
        for p in rows
    ]
