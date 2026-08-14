"""Binance Pay integration: order creation + webhook signature verification.

Signature scheme (HMAC-SHA512 over `timestamp\\nnonce\\nbody\\n`, hex-uppercased) matches
Binance Pay's merchant HMAC option. The live order call is stubbed until merchant creds
land (risk R2 in decisions). Frontend payment status is NEVER trusted — only the verified
webhook activates a subscription (decisions §2.4).
"""
from __future__ import annotations

import hashlib
import hmac

from app.core.config import settings


def create_order(order_id: str, amount, currency: str = "USDT") -> dict:
    # TODO(go-live): POST {BINANCE_PAY_BASE_URL}/binancepay/openapi/v3/order with signed request.
    return {
        "order_id": order_id,
        "checkout_url": f"https://pay.binance.com/checkout/{order_id}",
        "qr_content": f"binancepay://checkout/{order_id}",
        "amount": str(amount),
        "currency": currency,
    }


def verify_webhook_signature(timestamp: str, nonce: str, body: str, signature: str) -> bool:
    secret = settings.BINANCE_PAY_SECRET
    if not secret or not signature:
        return False
    payload = f"{timestamp}\n{nonce}\n{body}\n"
    expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha512).hexdigest().upper()
    return hmac.compare_digest(expected, signature.upper())
