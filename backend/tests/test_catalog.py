"""Catalog + approval workflow tests (S2)."""
from __future__ import annotations

import uuid

from app.core.security import create_access_token
from app.models import Role, User

API = "/api/v1"


def _auth(user_id: str) -> dict:
    token, _, _ = create_access_token(user_id)
    return {"Authorization": f"Bearer {token}"}


def _make_user(client, db, email, role=Role.customer) -> str:
    r = client.post(API + "/auth/register", json={"name": "U", "email": email, "password": "supersecret1"})
    assert r.status_code == 201, r.text
    uid = r.json()["user"]["id"]
    if role != Role.customer:
        u = db.get(User, uuid.UUID(uid))
        u.role = role
        db.commit()
    return uid


def _new_clip(client, editor_id, title="Monday Mood", access="free", **extra) -> str:
    body = {"title": title, "access": access, "language": "English", "layers": ["subtitle", "logo"], **extra}
    r = client.post(API + "/creator/clips", json=body, headers=_auth(editor_id))
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_full_flow_upload_approve_browse(client, db):
    editor = _make_user(client, db, "e@x.com", Role.editor)
    admin = _make_user(client, db, "adm@x.com", Role.admin)

    clip_id = _new_clip(client, editor, "Monday Mood", movie_name="3 Idiots", genre="Comedy")

    # not visible before approval
    assert client.get(API + "/clips").json()["total"] == 0

    # editor sees it in own uploads as pending
    ups = client.get(API + "/creator/clips", headers=_auth(editor)).json()
    assert ups[0]["status"] == "pending"

    # admin approves
    r = client.post(f"{API}/admin/clips/{clip_id}/approve", headers=_auth(admin))
    assert r.status_code == 200 and r.json()["status"] == "approved"

    # now browsable + searchable
    lst = client.get(API + "/clips", params={"q": "monday", "sort": "newest"}).json()
    assert lst["total"] == 1
    assert lst["items"][0]["editor_name"] == "U"
    assert lst["items"][0]["movie_name"] == "3 Idiots"


def test_customer_cannot_upload(client, db):
    cust = _make_user(client, db, "c@x.com", Role.customer)
    r = client.post(API + "/creator/clips", json={"title": "X"}, headers=_auth(cust))
    assert r.status_code == 403


def test_request_changes_then_resubmit(client, db):
    editor = _make_user(client, db, "e@x.com", Role.editor)
    admin = _make_user(client, db, "a@x.com", Role.admin)
    clip_id = _new_clip(client, editor)

    r = client.post(f"{API}/admin/clips/{clip_id}/request-changes", json={"note": "low-res base clip"}, headers=_auth(admin))
    assert r.json()["status"] == "changes" and r.json()["review_note"] == "low-res base clip"

    r2 = client.post(f"{API}/creator/clips/{clip_id}/submit", headers=_auth(editor))
    assert r2.json()["status"] == "pending" and r2.json()["review_note"] is None


def test_favorite_and_download(client, db):
    editor = _make_user(client, db, "e@x.com", Role.editor)
    admin = _make_user(client, db, "a@x.com", Role.admin)
    cust = _make_user(client, db, "c@x.com", Role.customer)
    clip_id = _new_clip(client, editor)
    client.post(f"{API}/admin/clips/{clip_id}/approve", headers=_auth(admin))

    assert client.post(f"{API}/clips/{clip_id}/favorite", headers=_auth(cust)).status_code == 201
    favs = client.get(API + "/me/favorites", headers=_auth(cust)).json()
    assert len(favs) == 1

    client.post(f"{API}/clips/{clip_id}/download", headers=_auth(cust))
    client.post(f"{API}/clips/{clip_id}/download", headers=_auth(cust))
    dls = client.get(API + "/me/downloads", headers=_auth(cust)).json()
    assert len(dls) == 2
    assert client.get(f"{API}/clips/{client.get(API + '/clips').json()['items'][0]['slug']}").json()["downloads"] == 2


def test_filter_by_category_and_feature(client, db):
    editor = _make_user(client, db, "e@x.com", Role.editor)
    admin = _make_user(client, db, "a@x.com", Role.admin)
    cat = client.post(API + "/admin/categories", json={"name": "Comedy"}, headers=_auth(admin)).json()
    clip_id = _new_clip(client, editor, "Comedy Cut", category_id=cat["id"])
    client.post(f"{API}/admin/clips/{clip_id}/approve", headers=_auth(admin))

    assert client.get(API + "/clips", params={"category": "comedy"}).json()["total"] == 1
    assert client.get(API + "/clips", params={"category": "nope"}).json()["total"] == 0

    # feature it
    r = client.post(f"{API}/admin/clips/{clip_id}/feature", headers=_auth(admin))
    assert r.json()["is_featured"] is True
    assert client.get(API + "/clips", params={"featured": "true"}).json()["total"] == 1
