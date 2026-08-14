"""Storage tests (S6): presigned upload/download via local signed endpoints."""
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
    uid = client.post(API + "/auth/register", json={"name": "U", "email": email, "password": "supersecret1"}).json()["user"]["id"]
    if role != Role.customer:
        u = db.get(User, uuid.UUID(uid))
        u.role = role
        db.commit()
    return uid


def test_upload_then_download(client, db, monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "STORAGE_DIR", str(tmp_path))
    editor = _mk(client, db, "e@x.com", Role.editor)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")

    # 1) editor requests a presigned upload URL
    uu = client.post(API + "/creator/upload-url", json={"filename": "clip.mp4", "content_type": "video/mp4"}, headers=_auth(editor)).json()
    assert uu["key"].startswith("clips/") and "token=" in uu["url"]

    # 2) editor uploads the bytes to the signed URL
    put = client.put(uu["url"], content=b"FAKE_MP4_BYTES")
    assert put.status_code == 200

    # 3) create the clip pointing at the uploaded key, admin approves
    cid = client.post(API + "/creator/clips", json={"title": "C", "access": "free", "base_clip_path": uu["key"]}, headers=_auth(editor)).json()["id"]
    client.post(f"{API}/admin/clips/{cid}/approve", headers=_auth(admin))

    # 4) customer gets an access-gated download URL and fetches the file
    du = client.post(f"{API}/clips/{cid}/download-url", headers=_auth(cust)).json()
    assert du["downloads"] == 1
    got = client.get(du["url"])
    assert got.status_code == 200 and got.content == b"FAKE_MP4_BYTES"


def test_tampered_token_rejected(client, db, monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "STORAGE_DIR", str(tmp_path))
    r = client.get("/api/v1/storage/clips/x/clip.mp4?exp=9999999999&token=deadbeef")
    assert r.status_code == 403


def test_download_url_without_file_conflicts(client, db):
    editor = _mk(client, db, "e@x.com", Role.editor)
    admin = _mk(client, db, "a@x.com", Role.admin)
    cust = _mk(client, db, "c@x.com")
    cid = client.post(API + "/creator/clips", json={"title": "C", "access": "free"}, headers=_auth(editor)).json()["id"]
    client.post(f"{API}/admin/clips/{cid}/approve", headers=_auth(admin))
    r = client.post(f"{API}/clips/{cid}/download-url", headers=_auth(cust))
    assert r.status_code == 409
