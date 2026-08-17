"""Editor earnings + payout workflow tests (S4)."""
from __future__ import annotations

import uuid

from app.core.config import settings
from app.core.security import create_access_token
from app.models import Role, User

API = "/api/v1"


def _auth(uid: str) -> dict:
    token, _, _ = create_access_token(uid)
    return {"Authorization": f"Bearer {token}"}


def _mk(client, db, email, role=Role.customer) -> str:
    uid = client.post(API + "/auth/register", json={"name": "U-" + email, "email": email, "password": "supersecret1", "device": {"device_id": "dev-" + email}}).json()["user"]["id"]
    if role != Role.customer:
        u = db.get(User, uuid.UUID(uid))
        u.role = role
        db.commit()
    return uid


def _approved_clip(client, editor, admin):
    cid = client.post(API + "/creator/clips", json={"title": "Clip", "access": "free"}, headers=_auth(editor)).json()["id"]
    client.post(f"{API}/admin/clips/{cid}/approve", headers=_auth(admin))
    return cid


def test_earnings_and_payout_flow(client, db, monkeypatch):
    monkeypatch.setattr(settings, "PAYOUT_RATE_PER_DOWNLOAD", 1.0)
    editor = _mk(client, db, "e@x.com", Role.editor)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    cid = _approved_clip(client, editor, admin)

    for _ in range(5):
        assert client.post(f"{API}/clips/{cid}/download", headers=_auth(cust)).status_code == 201

    earn = client.get(API + "/creator/earnings", headers=_auth(editor)).json()
    assert earn["downloads"] == 5 and earn["earned"] == 5.0 and earn["available"] == 5.0

    # request payout of 3
    r = client.post(API + "/creator/payouts", json={"amount": 3}, headers=_auth(editor))
    assert r.status_code == 201 and r.json()["status"] == "pending"
    payout_id = r.json()["id"]

    earn = client.get(API + "/creator/earnings", headers=_auth(editor)).json()
    assert earn["pending"] == 3.0 and earn["available"] == 2.0

    # cannot over-request
    assert client.post(API + "/creator/payouts", json={"amount": 5}, headers=_auth(editor)).status_code == 400

    # admin sees + marks paid
    q = client.get(API + "/admin/payouts", params={"status_filter": "pending"}, headers=_auth(admin)).json()
    assert len(q) == 1 and q[0]["editor_name"] == "U-e@x.com"

    mp = client.post(f"{API}/admin/payouts/{payout_id}/mark-paid", headers=_auth(admin))
    assert mp.status_code == 200 and mp.json()["status"] == "paid" and mp.json()["paid_at"]

    earn = client.get(API + "/creator/earnings", headers=_auth(editor)).json()
    assert earn["paid"] == 3.0 and earn["pending"] == 0.0 and earn["available"] == 2.0


def test_reject_frees_balance(client, db, monkeypatch):
    monkeypatch.setattr(settings, "PAYOUT_RATE_PER_DOWNLOAD", 1.0)
    editor = _mk(client, db, "e@x.com", Role.editor)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    cid = _approved_clip(client, editor, admin)
    for _ in range(2):
        client.post(f"{API}/clips/{cid}/download", headers=_auth(cust))

    pid = client.post(API + "/creator/payouts", json={"amount": 2}, headers=_auth(editor)).json()["id"]
    assert client.get(API + "/creator/earnings", headers=_auth(editor)).json()["available"] == 0.0

    client.post(f"{API}/admin/payouts/{pid}/reject", json={"note": "bad details"}, headers=_auth(admin))
    assert client.get(API + "/creator/earnings", headers=_auth(editor)).json()["available"] == 2.0


def test_customer_cannot_see_earnings(client, db):
    cust = _mk(client, db, "c@x.com")
    assert client.get(API + "/creator/earnings", headers=_auth(cust)).status_code == 403
