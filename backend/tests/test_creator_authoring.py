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
