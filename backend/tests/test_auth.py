"""Auth feature tests (decisions §6, §7)."""
from __future__ import annotations

from app.services import google as google_service


def _register(client, email="a@x.com", device_id="dev-1"):
    return client.post(
        "/api/v1/auth/register",
        json={
            "name": "Aditya",
            "email": email,
            "password": "supersecret1",
            "device": {"device_id": device_id, "os": "iOS 17"},
        },
    )


def test_register_login_me(client):
    r = _register(client)
    assert r.status_code == 201, r.text
    data = r.json()
    assert data["user"]["email"] == "a@x.com"
    assert data["user"]["role"] == "customer"
    access = data["tokens"]["access_token"]

    me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {access}"})
    assert me.status_code == 200
    assert me.json()["email"] == "a@x.com"


def test_duplicate_email_rejected(client):
    assert _register(client).status_code == 201
    assert _register(client).status_code == 409


def test_login_wrong_password(client):
    _register(client)
    r = client.post("/api/v1/auth/login", json={"email": "a@x.com", "password": "nope"})
    assert r.status_code == 401


def test_device_binding_limit(client):
    _register(client, device_id="dev-1")
    # second device ok
    r2 = client.post(
        "/api/v1/auth/login",
        json={"email": "a@x.com", "password": "supersecret1", "device": {"device_id": "dev-2"}},
    )
    assert r2.status_code == 200
    # third device blocked (max 2)
    r3 = client.post(
        "/api/v1/auth/login",
        json={"email": "a@x.com", "password": "supersecret1", "device": {"device_id": "dev-3"}},
    )
    assert r3.status_code == 409
    assert r3.json()["detail"]["code"] == "device_limit"
    assert len(r3.json()["detail"]["devices"]) == 2


def test_refresh_rotates(client):
    tokens = _register(client).json()["tokens"]
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    new = r.json()
    assert new["access_token"] != tokens["access_token"]
    # old refresh now revoked
    again = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert again.status_code == 401


def test_google_login(client, monkeypatch):
    def fake_verify(_token):
        return google_service.GoogleIdentity(sub="g-123", email="g@x.com", name="Goog User")

    monkeypatch.setattr(google_service, "verify_google_token", fake_verify)
    r = client.post(
        "/api/v1/auth/google",
        json={"id_token": "whatever", "device": {"device_id": "gdev"}},
    )
    assert r.status_code == 200, r.text
    assert r.json()["user"]["email"] == "g@x.com"


def test_me_requires_auth(client):
    assert client.get("/api/v1/auth/me").status_code in (401, 403)
