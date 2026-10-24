"""The caption looks the editor offers, and who gets to change them.

A preset is a complete caption look. Complete matters: the presets it replaces
set five fields and left the rest alone, so applying one gave a different
result depending on what the caption happened to look like before, and a set
of captions styled by the same tap did not match.

These presets are also the one product decision in the app that an admin can
change without a release, so the write path has to be strict - a bad list
reaches every customer's editor - and the read path has to keep working when
nobody has saved anything at all.
"""
from __future__ import annotations

import uuid

from app.models import Role, User
from app.services import presets as preset_service

API = "/api/v1"


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


def _auth(client, db, email, role) -> dict:
    from app.core.security import create_access_token
    uid = _make_user(client, db, email, role)
    token, _, _ = create_access_token(uid)
    return {"Authorization": f"Bearer {token}"}


# ---- what the app reads ---------------------------------------------------

def test_the_editor_can_read_presets_without_signing_in(client):
    # The preset row is drawn before sign-in has finished, and these say
    # nothing about an account.
    r = client.get(API + "/config/caption-presets")
    assert r.status_code == 200
    assert len(r.json()["presets"]) > 0


def test_every_preset_arrives_complete(client):
    """The whole point: no field left for the previous look to fill in."""
    presets = client.get(API + "/config/caption-presets").json()["presets"]
    for p in presets:
        missing = set(preset_service.FIELD_DEFAULTS) - set(p)
        assert not missing, f"{p['name']} is missing {sorted(missing)}"
        assert p["name"].strip()


def test_with_nothing_saved_the_defaults_are_what_is_served(client):
    served = client.get(API + "/config/caption-presets").json()["presets"]
    assert served == preset_service.defaults()


# ---- who may change them --------------------------------------------------

def test_a_customer_cannot_change_what_everyone_sees(client, db):
    h = _auth(client, db, "c-pre@x.com", Role.customer)
    r = client.put(f"{API}/admin/caption-presets",
                   json={"presets": [{"name": "Mine"}]}, headers=h)
    assert r.status_code == 403


def test_an_admin_saves_and_the_app_serves_it(client, db):
    h = _auth(client, db, "a-pre@x.com", Role.admin)
    r = client.put(f"{API}/admin/caption-presets", headers=h, json={"presets": [
        {"name": "House style", "font": "Anton", "fontSize": 61, "color": "#FFFF0000"},
    ]})
    assert r.status_code == 200, r.text

    served = client.get(API + "/config/caption-presets").json()["presets"]
    assert len(served) == 1
    assert served[0]["name"] == "House style"
    assert served[0]["fontSize"] == 61
    assert served[0]["color"] == "#FFFF0000"
    # and the ones it did not mention still arrived
    assert served[0]["lineHeight"] == preset_service.FIELD_DEFAULTS["lineHeight"]


def test_saving_again_replaces_rather_than_appends(client, db):
    h = _auth(client, db, "a-pre2@x.com", Role.admin)
    client.put(f"{API}/admin/caption-presets", headers=h,
               json={"presets": [{"name": "One"}, {"name": "Two"}]})
    client.put(f"{API}/admin/caption-presets", headers=h,
               json={"presets": [{"name": "Only"}]})
    served = client.get(API + "/config/caption-presets").json()["presets"]
    assert [p["name"] for p in served] == ["Only"]


def test_the_admin_is_shown_the_defaults_alongside_what_is_live(client, db):
    h = _auth(client, db, "a-pre3@x.com", Role.admin)
    body = client.get(f"{API}/admin/caption-presets", headers=h).json()
    assert body["defaults"] == preset_service.defaults()


# ---- a bad list must not reach anybody's editor ---------------------------

def test_what_is_rejected_says_which_preset_and_which_field(client, db):
    h = _auth(client, db, "a-bad@x.com", Role.admin)

    def put(presets):
        return client.put(f"{API}/admin/caption-presets", headers=h, json={"presets": presets})

    assert put([]).status_code == 422
    assert put("not a list").status_code == 422
    assert put([{"name": "  "}]).status_code == 422

    # names have to differ, and case is not a difference
    r = put([{"name": "Dupe"}, {"name": "dupe"}])
    assert r.status_code == 422 and "dupe" in r.json()["detail"].lower()

    r = put([{"name": "Bad anim", "anim": "explode"}])
    assert r.status_code == 422 and "anim" in r.json()["detail"]

    r = put([{"name": "Bad align", "align": "middle"}])
    assert r.status_code == 422 and "align" in r.json()["detail"]

    r = put([{"name": "Bad colour", "color": "red"}])
    assert r.status_code == 422 and "color" in r.json()["detail"]

    r = put([{"name": "Bad size", "fontSize": "big"}])
    assert r.status_code == 422 and "fontSize" in r.json()["detail"]


def test_a_rejected_save_leaves_the_live_list_alone(client, db):
    h = _auth(client, db, "a-keep@x.com", Role.admin)
    client.put(f"{API}/admin/caption-presets", headers=h, json={"presets": [{"name": "Good"}]})
    client.put(f"{API}/admin/caption-presets", headers=h, json={"presets": [{"name": "X", "anim": "nope"}]})
    served = client.get(API + "/config/caption-presets").json()["presets"]
    assert [p["name"] for p in served] == ["Good"]
