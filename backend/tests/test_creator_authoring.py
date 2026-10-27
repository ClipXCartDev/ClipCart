"""What a creator may ship with a clip, and what they may not.

A clip's `overlays` are the layers a creator lays out — captions, a CTA, a
handle, their own mark — and every customer who opens that clip gets them
applied on their phone. That makes this payload the one place where one
account's input is executed on everybody else's device, so the shape of it is
checked here rather than trusted.
"""
from __future__ import annotations

import uuid

from app.core.security import create_access_token
from app.models import Role, User

API = "/api/v1"


def _editor(client, db, email="e-auth@x.com") -> dict:
    r = client.post(API + "/auth/register", json={
        "name": "E", "email": email, "password": "supersecret1",
        "device": {"device_id": "dev-" + email}})
    assert r.status_code == 201, r.text
    uid = r.json()["user"]["id"]
    u = db.get(User, uuid.UUID(uid))
    u.role = Role.editor
    db.commit()
    token, _, _ = create_access_token(uid)
    return {"Authorization": f"Bearer {token}"}


SRT = "1\n00:00:01,000 --> 00:00:03,000\nHello\n\n2\n00:00:04,000 --> 00:00:05,000\nAgain\n"


# ---- subtitles come from the server, once ---------------------------------

def test_a_creator_turns_an_srt_into_caption_layers(client, db):
    h = _editor(client, db)
    r = client.post(f"{API}/creator/subtitles/parse", headers=h, json={"text": SRT})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["count"] == 2
    assert [c["t"] for c in body["captions"]] == ["Hello", "Again"]
    # ready to drop into overlays.subs as-is
    assert body["captions"][0]["k"] == "text"
    assert body["captions"][0]["s"] == 1.0


def test_captions_past_the_end_of_the_clip_are_dropped(client, db):
    h = _editor(client, db, "e-dur@x.com")
    r = client.post(f"{API}/creator/subtitles/parse", headers=h,
                    json={"text": SRT, "duration": 3.0})
    assert [c["t"] for c in r.json()["captions"]] == ["Hello"]


def test_an_unreadable_file_says_what_was_expected(client, db):
    h = _editor(client, db, "e-bad@x.com")
    r = client.post(f"{API}/creator/subtitles/parse", headers=h, json={"text": "notes only"})
    assert r.status_code == 422
    assert "-->" in r.json()["detail"]["message"]


def test_a_customer_cannot_use_the_parser(client, db):
    r = client.post(API + "/auth/register", json={
        "name": "C", "email": "c-srt@x.com", "password": "supersecret1",
        "device": {"device_id": "d-c-srt"}})
    token, _, _ = create_access_token(r.json()["user"]["id"])
    r = client.post(f"{API}/creator/subtitles/parse",
                    headers={"Authorization": f"Bearer {token}"}, json={"text": SRT})
    assert r.status_code == 403


# ---- the creator's mark -----------------------------------------------------

def test_a_mark_is_uploaded_under_its_own_prefix(client, db):
    h = _editor(client, db, "e-mark@x.com")
    r = client.post(f"{API}/creator/upload-url", headers=h,
                    json={"filename": "logo.png", "content_type": "image/png"})
    assert r.status_code == 200, r.text
    # separate from clips/, so the key guard on each cannot reach the other's
    assert r.json()["key"].startswith("marks/")


def test_a_clip_is_still_the_only_thing_that_can_be_a_video(client, db):
    h = _editor(client, db, "e-vid@x.com")
    assert client.post(f"{API}/creator/upload-url", headers=h, json={
        "filename": "c.mp4", "content_type": "video/mp4"}).json()["key"].startswith("clips/")
    r = client.post(f"{API}/creator/upload-url", headers=h,
                    json={"filename": "x.exe", "content_type": "application/octet-stream"})
    assert r.status_code == 422


def _make_clip(client, h, overlays):
    return client.post(f"{API}/creator/clips", headers=h, json={
        "title": "authored", "access": "free", "language": "English",
        "base_clip_path": f"clips/{uuid.uuid4()}/raw.mp4",
        "overlays": overlays,
    })


def test_a_clip_keeps_the_mark_as_a_key_and_hands_out_a_signed_url(client, db):
    h = _editor(client, db, "e-key@x.com")
    key = f"marks/{uuid.uuid4()}/logo.png"
    r = _make_clip(client, h, {"subs": [], "logoKey": key})
    assert r.status_code == 201, r.text
    ov = r.json()["overlays"]
    assert ov["logoKey"] == key
    # signed per request, because a URL stored at upload time would have long
    # expired by the time a customer opened the clip
    assert ov["logoUrl"].startswith("http") or ov["logoUrl"].startswith("/")


def test_a_creator_cannot_point_every_customer_at_a_url_they_chose(client, db):
    """The customer's app downloads whatever this field names, onto their phone."""
    h = _editor(client, db, "e-ssrf@x.com")
    r = _make_clip(client, h, {"subs": [], "logoUrl": "https://example.com/evil.png"})
    assert r.status_code == 201, r.text
    ov = r.json()["overlays"]
    assert "example.com" not in str(ov)
    assert ov.get("logoUrl") is None


def test_a_mark_key_from_somewhere_else_is_refused(client, db):
    h = _editor(client, db, "e-badkey@x.com")
    for bad in ["clips/x/raw.mp4", "../../etc/passwd", "marks/not-a-uuid/x.png", 7]:
        r = _make_clip(client, h, {"subs": [], "logoKey": bad})
        assert r.status_code == 422, f"{bad!r} was accepted"


def test_a_device_local_path_never_reaches_the_catalogue(client, db):
    # The app strips it, but the app is not what this has to be true of.
    h = _editor(client, db, "e-path@x.com")
    r = _make_clip(client, h, {"subs": [], "logoPath": "/data/user/0/app/files/logo.png"})
    assert r.status_code == 201
    assert "logoPath" not in r.json()["overlays"]


def test_the_same_rules_apply_when_a_clip_is_edited(client, db):
    h = _editor(client, db, "e-upd@x.com")
    clip_id = _make_clip(client, h, {"subs": []}).json()["id"]
    r = client.put(f"{API}/creator/clips/{clip_id}", headers=h,
                   json={"overlays": {"subs": [], "logoUrl": "https://example.com/evil.png"}})
    assert r.status_code == 200, r.text
    assert "example.com" not in str(r.json()["overlays"])

    r = client.put(f"{API}/creator/clips/{clip_id}", headers=h,
                   json={"overlays": {"subs": [], "logoKey": "clips/x/y.mp4"}})
    assert r.status_code == 422


def test_authored_captions_survive_the_round_trip(client, db):
    """What the creator laid out is what the customer's editor will read."""
    h = _editor(client, db, "e-round@x.com")
    caps = client.post(f"{API}/creator/subtitles/parse", headers=h,
                       json={"text": SRT}).json()["captions"]
    clip_id = _make_clip(client, h, {"subs": caps, "authoredShort": 1080}).json()["id"]

    back = client.get(f"{API}/creator/clips", headers=h).json()
    mine = next(c for c in back if c["id"] == clip_id)
    assert [s["t"] for s in mine["overlays"]["subs"]] == ["Hello", "Again"]
    assert mine["overlays"]["authoredShort"] == 1080


# ---- somebody has to be able to make a creator ----------------------------

def _admin(client, db, email="a-role@x.com") -> tuple[dict, str]:
    r = client.post(API + "/auth/register", json={
        "name": "A", "email": email, "password": "supersecret1",
        "device": {"device_id": "d-" + email}})
    uid = r.json()["user"]["id"]
    u = db.get(User, uuid.UUID(uid))
    u.role = Role.admin
    db.commit()
    token, _, _ = create_access_token(uid)
    return {"Authorization": f"Bearer {token}"}, uid


def test_an_admin_can_turn_a_customer_into_a_creator(client, db):
    # Until this existed a creator could only be made from a database shell,
    # so the people who run this could not onboard one at all.
    h, _ = _admin(client, db)
    r = client.post(API + "/auth/register", json={
        "name": "C", "email": "c-promote@x.com", "password": "supersecret1",
        "device": {"device_id": "d-promote"}})
    uid = r.json()["user"]["id"]

    r = client.post(f"{API}/admin/users/{uid}/role", headers=h, json={"role": "editor"})
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "editor"

    # and the promotion is what the creator endpoints actually go on
    token, _, _ = create_access_token(uid)
    r = client.post(f"{API}/creator/upload-url",
                    headers={"Authorization": f"Bearer {token}"},
                    json={"filename": "c.mp4", "content_type": "video/mp4"})
    assert r.status_code == 200


def test_a_creator_can_be_turned_back_into_a_customer(client, db):
    h, _ = _admin(client, db, "a-demote@x.com")
    r = client.post(API + "/auth/register", json={
        "name": "E", "email": "e-demote@x.com", "password": "supersecret1",
        "device": {"device_id": "d-demote"}})
    uid = r.json()["user"]["id"]
    client.post(f"{API}/admin/users/{uid}/role", headers=h, json={"role": "editor"})
    r = client.post(f"{API}/admin/users/{uid}/role", headers=h, json={"role": "customer"})
    assert r.json()["role"] == "customer"


def test_an_admin_cannot_demote_themselves_out_of_the_console(client, db):
    h, uid = _admin(client, db, "a-self@x.com")
    r = client.post(f"{API}/admin/users/{uid}/role", headers=h, json={"role": "customer"})
    assert r.status_code == 409


def test_a_role_that_is_not_a_role_is_refused(client, db):
    h, _ = _admin(client, db, "a-bad-role@x.com")
    r = client.post(API + "/auth/register", json={
        "name": "C", "email": "c-badrole@x.com", "password": "supersecret1",
        "device": {"device_id": "d-badrole"}})
    uid = r.json()["user"]["id"]
    r = client.post(f"{API}/admin/users/{uid}/role", headers=h, json={"role": "superuser"})
    assert r.status_code == 422


def test_a_creator_cannot_promote_anybody(client, db):
    h = _editor(client, db, "e-noprom@x.com")
    r = client.post(API + "/auth/register", json={
        "name": "C", "email": "c-noprom@x.com", "password": "supersecret1",
        "device": {"device_id": "d-noprom"}})
    uid = r.json()["user"]["id"]
    r = client.post(f"{API}/admin/users/{uid}/role", headers=h, json={"role": "admin"})
    assert r.status_code == 403
