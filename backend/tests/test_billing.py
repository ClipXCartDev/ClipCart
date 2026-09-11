"""Billing tests: plans, Binance Pay checkout + signed webhook, Pro/quota gate (S3)."""
from __future__ import annotations

import hashlib
import hmac
import json
import uuid

from app.core.config import settings
from app.core.security import create_access_token
from app.models import Role, User

API = "/api/v1"
SECRET = "testsecret"


def _auth(uid: str) -> dict:
    token, _, _ = create_access_token(uid)
    return {"Authorization": f"Bearer {token}"}


def _mk(client, db, email, role=Role.customer) -> str:
    uid = client.post(API + "/auth/register", json={"name": "U", "email": email, "password": "supersecret1", "device": {"device_id": "dev-" + email}}).json()["user"]["id"]
    if role != Role.customer:
        u = db.get(User, uuid.UUID(uid))
        u.role = role
        db.commit()
    return uid


def _plan(client, admin, name="Professional", price=9, export_limit=None):
    return client.post(
        API + "/admin/plans",
        json={"name": name, "price_usd": price, "export_limit": export_limit},
        headers=_auth(admin),
    ).json()


def _approved_clip(client, editor, admin, access="free"):
    cid = client.post(API + "/creator/clips", json={"title": "Clip", "access": access}, headers=_auth(editor)).json()["id"]
    client.post(f"{API}/admin/clips/{cid}/approve", headers=_auth(admin))
    return cid


def _webhook(client, order_id, biz="PAY_SUCCESS"):
    body = json.dumps({"bizStatus": biz, "data": json.dumps({"merchantTradeNo": order_id})})
    ts, nonce = "1700000000000", "nonce123"
    sig = hmac.new(SECRET.encode(), f"{ts}\n{nonce}\n{body}\n".encode(), hashlib.sha512).hexdigest().upper()
    return client.post(
        API + "/billing/webhook",
        content=body,
        headers={
            "BinancePay-Timestamp": ts,
            "BinancePay-Nonce": nonce,
            "BinancePay-Signature": sig,
            "Content-Type": "application/json",
        },
    )


def test_plans_public(client, db):
    admin = _mk(client, db, "a@x.com", Role.admin)
    _plan(client, admin)
    plans = client.get(API + "/billing/plans").json()
    assert len(plans) == 1 and plans[0]["name"] == "Professional"


def test_checkout_and_webhook_activates(client, db, monkeypatch):
    monkeypatch.setattr(settings, "BINANCE_PAY_SECRET", SECRET)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    plan = _plan(client, admin)

    co = client.post(API + "/billing/checkout", json={"plan_id": plan["id"]}, headers=_auth(cust)).json()
    assert co["order_id"].startswith("cc-")
    assert client.get(API + "/billing/subscription", headers=_auth(cust)).json() is None

    r = _webhook(client, co["order_id"])
    assert r.status_code == 200 and r.json()["returnCode"] == "SUCCESS"

    sub = client.get(API + "/billing/subscription", headers=_auth(cust)).json()
    assert sub is not None and sub["status"] == "active"
    pays = client.get(API + "/billing/payments", headers=_auth(cust)).json()
    assert pays[0]["status"] == "paid"


def test_webhook_bad_signature(client, db, monkeypatch):
    monkeypatch.setattr(settings, "BINANCE_PAY_SECRET", SECRET)
    r = client.post(
        API + "/billing/webhook",
        content=json.dumps({"bizStatus": "PAY_SUCCESS"}),
        headers={"BinancePay-Timestamp": "1", "BinancePay-Nonce": "n", "BinancePay-Signature": "DEADBEEF"},
    )
    assert r.status_code == 401


def test_pro_clip_requires_subscription(client, db, monkeypatch):
    monkeypatch.setattr(settings, "BINANCE_PAY_SECRET", SECRET)
    editor = _mk(client, db, "e@x.com", Role.editor)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    pro = _approved_clip(client, editor, admin, access="pro")

    # blocked without subscription
    r = client.post(f"{API}/clips/{pro}/download", headers=_auth(cust))
    assert r.status_code == 402 and r.json()["detail"]["code"] == "subscription_required"

    # subscribe, then allowed
    plan = _plan(client, admin)
    co = client.post(API + "/billing/checkout", json={"plan_id": plan["id"]}, headers=_auth(cust)).json()
    _webhook(client, co["order_id"])
    assert client.post(f"{API}/clips/{pro}/download", headers=_auth(cust)).status_code == 201


def test_monthly_quota(client, db, monkeypatch):
    monkeypatch.setattr(settings, "BINANCE_PAY_SECRET", SECRET)
    editor = _mk(client, db, "e@x.com", Role.editor)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    free = _approved_clip(client, editor, admin, access="free")
    plan = _plan(client, admin, name="Basic", price=4, export_limit=1)
    co = client.post(API + "/billing/checkout", json={"plan_id": plan["id"]}, headers=_auth(cust)).json()
    _webhook(client, co["order_id"])

    other = _approved_clip(client, editor, admin, access="free")

    assert client.post(f"{API}/clips/{free}/download", headers=_auth(cust)).status_code == 201
    # the same clip again is NOT a second purchase (one credit per clip) ...
    assert client.post(f"{API}/clips/{free}/download", headers=_auth(cust)).status_code == 201
    # ... but a different clip needs a credit the period no longer has
    r = client.post(f"{API}/clips/{other}/download", headers=_auth(cust))
    assert r.status_code == 402 and r.json()["detail"]["code"] == "quota_exceeded"


def test_one_credit_per_clip_and_final(client, db, monkeypatch):
    """One edit == one purchase: opening a clip charges once, reopening is free,
    exporting makes it final, and credits count within the paid period."""
    monkeypatch.setattr(settings, "BINANCE_PAY_SECRET", SECRET)
    editor = _mk(client, db, "e@x.com", Role.editor)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    uu = client.post(API + "/creator/upload-url", json={"filename": "a.mp4", "content_type": "video/mp4"}, headers=_auth(editor)).json()
    a = client.post(API + "/creator/clips", json={"title": "A", "access": "free", "base_clip_path": uu["key"]}, headers=_auth(editor)).json()["id"]
    b = client.post(API + "/creator/clips", json={"title": "B", "access": "free", "base_clip_path": uu["key"]}, headers=_auth(editor)).json()["id"]
    for cid in (a, b):
        client.post(f"{API}/admin/clips/{cid}/approve", headers=_auth(admin))
    plan = _plan(client, admin, name="Basic", price=4, export_limit=1)
    co = client.post(API + "/billing/checkout", json={"plan_id": plan["id"]}, headers=_auth(cust)).json()
    _webhook(client, co["order_id"])

    st = client.get(f"{API}/clips/{a}/edit-state", headers=_auth(cust)).json()
    assert st == {"charged": False, "exported": False, "exported_at": None, "credits_left": 1, "subscribed": True}

    # first open charges the single credit ...
    r1 = client.post(f"{API}/clips/{a}/download-url", headers=_auth(cust)).json()
    assert r1["charged"] is True and r1["credits_left"] == 0 and r1["downloads"] == 1
    # ... reopening the same clip is free (no second row, no second download count)
    r2 = client.post(f"{API}/clips/{a}/download-url", headers=_auth(cust)).json()
    assert r2["charged"] is False and r2["credits_left"] == 0 and r2["downloads"] == 1
    assert client.get(API + "/billing/subscription", headers=_auth(cust)).json()["edit_credits"] == 0
    # another clip needs another credit -> exhausted
    r3 = client.post(f"{API}/clips/{b}/download-url", headers=_auth(cust))
    assert r3.status_code == 402 and r3.json()["detail"]["code"] == "quota_exceeded"

    # export -> final; idempotent; still openable for the paid clip
    assert client.post(f"{API}/clips/{b}/finalize", headers=_auth(cust)).status_code == 409
    f1 = client.post(f"{API}/clips/{a}/finalize", headers=_auth(cust)).json()
    assert f1["charged"] and f1["exported"] and f1["exported_at"]
    f2 = client.post(f"{API}/clips/{a}/finalize", headers=_auth(cust)).json()
    assert f2["exported_at"] == f1["exported_at"]
    assert client.post(f"{API}/clips/{a}/download-url", headers=_auth(cust)).json()["exported"] is True


def test_admin_grant_plan(client, db):
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    _plan(client, admin, name="Professional")
    uid = client.get(API + "/auth/me", headers=_auth(cust)).json()["id"]
    r = client.post(f"{API}/admin/users/{uid}/grant", json={"plan_slug": "professional", "days": 7}, headers=_auth(admin))
    assert r.status_code == 200 and r.json()["plan"] == "professional"
    sub = client.get(API + "/billing/subscription", headers=_auth(cust)).json()
    assert sub["status"] == "active" and sub["plan_name"] == "Professional" and sub["edit_credits"] is None
    # customers can't grant
    assert client.post(f"{API}/admin/users/{uid}/grant", json={"plan_slug": "professional"}, headers=_auth(cust)).status_code == 403
