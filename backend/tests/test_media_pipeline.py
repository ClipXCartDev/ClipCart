"""The rule that keeps a clip from reaching a customer without playable media.

A creator's upload is a raw file. Its preview and poster are derived from it,
and until that has happened the clip has nothing to show: the API signs those
URLs from the clip's id alone, so a clip always *looks* like it has media. The
first thing a customer actually saw was a blank tile, a player that showed
nothing and an editor that refused to open — after a credit had been spent.

These tests hold the line that was missing: approval cannot pass a clip whose
media is not ready, and the catalogue cannot list one.
"""
from __future__ import annotations

import uuid

from app.core.security import create_access_token
from app.models import Clip, ClipStatus, Role, User
from app.worker import derive

API = "/api/v1"


def _auth(user_id: str) -> dict:
    token, _, _ = create_access_token(user_id)
    return {"Authorization": f"Bearer {token}"}


def _make_user(client, db, email, role=Role.customer) -> str:
    r = client.post(API + "/auth/register", json={
        "name": "U", "email": email, "password": "supersecret1",
        "device": {"device_id": "dev-" + email}})
    assert r.status_code == 201, r.text
    uid = r.json()["user"]["id"]
    if role != Role.customer:
        u = db.get(User, uuid.UUID(uid))
        u.role = role
        db.commit()
    return uid


def _uploaded_clip(client, db, editor_id, media_status="pending") -> Clip:
    """A clip as it exists the moment a creator finishes uploading: a raw file
    and nothing derived from it yet."""
    r = client.post(API + "/creator/clips", json={
        "title": "raw upload", "access": "free", "language": "English",
        "base_clip_path": f"clips/{uuid.uuid4()}/raw.mp4",
    }, headers=_auth(editor_id))
    assert r.status_code == 201, r.text
    clip = db.get(Clip, uuid.UUID(r.json()["id"]))
    clip.media_status = media_status
    db.commit()
    db.refresh(clip)
    return clip


# ---- the worker writes where the API looks -------------------------------

def test_derived_keys_come_from_the_clip_id():
    # The API signs these keys without checking anything exists at them, so the
    # worker has to write to exactly the same place or the URLs point at air.
    cid = uuid.uuid4()
    assert derive.preview_key(cid) == f"previews/{cid}.mp4"
    assert derive.thumb_key(cid) == f"thumbs/{cid}.jpg"


def test_aspect_label_recognises_the_shapes_the_app_offers():
    assert derive._aspect_label(1080, 1920) == "9:16"
    assert derive._aspect_label(1080, 1080) == "1:1"
    assert derive._aspect_label(1920, 1080) == "16:9"
    assert derive._aspect_label(1080, 1350) == "4:5"
    # something odd is left alone rather than forced into a label
    assert derive._aspect_label(1000, 333) is None
    assert derive._aspect_label(0, 0) is None


# ---- approval is the gate -------------------------------------------------

def test_approval_refuses_a_clip_whose_media_is_not_ready(client, db):
    editor = _make_user(client, db, "e-media@x.com", Role.editor)
    admin = _make_user(client, db, "a-media@x.com", Role.admin)
    clip = _uploaded_clip(client, db, editor)

    r = client.post(f"{API}/admin/clips/{clip.id}/approve", headers=_auth(admin))
    assert r.status_code == 409
    assert r.json()["detail"]["code"] == "media_not_ready"
    db.refresh(clip)
    assert clip.status == ClipStatus.pending


def test_approval_tells_a_failed_derive_apart_from_one_still_running(client, db):
    editor = _make_user(client, db, "e-fail@x.com", Role.editor)
    admin = _make_user(client, db, "a-fail@x.com", Role.admin)
    clip = _uploaded_clip(client, db, editor, media_status="failed")

    detail = client.post(f"{API}/admin/clips/{clip.id}/approve",
                         headers=_auth(admin)).json()["detail"]
    assert detail["media_status"] == "failed"
    # the two states need different words: one is "wait", the other is "re-upload"
    assert "re-upload" in detail["message"]


def test_approval_passes_once_the_media_is_there(client, db):
    editor = _make_user(client, db, "e-ok@x.com", Role.editor)
    admin = _make_user(client, db, "a-ok@x.com", Role.admin)
    clip = _uploaded_clip(client, db, editor, media_status="ready")

    r = client.post(f"{API}/admin/clips/{clip.id}/approve", headers=_auth(admin))
    assert r.status_code == 200, r.text
    db.refresh(clip)
    assert clip.status == ClipStatus.approved


def test_the_catalogue_hides_an_approved_clip_that_lost_its_media(client, db):
    """Belt and braces. Approval is the gate, but a clip approved before this
    existed — or one whose files are later removed — must not show up either."""
    editor = _make_user(client, db, "e-cat@x.com", Role.editor)
    admin = _make_user(client, db, "a-cat@x.com", Role.admin)
    clip = _uploaded_clip(client, db, editor, media_status="ready")
    client.post(f"{API}/admin/clips/{clip.id}/approve", headers=_auth(admin))

    items = client.get(API + "/clips?limit=60").json()["items"]
    assert any(c["id"] == str(clip.id) for c in items)

    clip.media_status = "pending"
    db.commit()
    items = client.get(API + "/clips?limit=60").json()["items"]
    assert not any(c["id"] == str(clip.id) for c in items)
