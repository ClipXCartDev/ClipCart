"""Rebuild the 91-clip catalog from the public-API backup.

Original ids/slugs/titles/categories are preserved, so the R2 objects that
already exist (thumbs/{id}.jpg, previews/{id}.mp4) re-attach for free - both
keys are derived from the clip id.

base_clip_path is NOT in the backup (clips/{random-uuid}/{file} is never
exposed by the public API), so every row gets a placeholder here and
match_raw.py + apply_mapping.py recover the real keys by content.
"""
import json
import sys
import uuid
from datetime import datetime, timezone

sys.path.insert(0, "/app")
import app.models  # noqa: F401  (register mappers)
from app.db.session import SessionLocal
from app.models import User
from app.models.catalog import Access, Category, Clip, ClipStatus

RAW_PLACEHOLDER = "clips/00000000-0000-0000-0000-000000000000/pending-relink.mp4"


def ts(v):
    if not v:
        return None
    return datetime.fromisoformat(v.replace("Z", "+00:00")).astimezone(timezone.utc)


data = json.load(open("/app/restore/catalog_restore.json"))
clips, cats = data["clips"], data["categories"]
db = SessionLocal()

editor = db.query(User).filter_by(email="editor@clipcart.app").first()
assert editor, "editor@clipcart.app missing - run seed.py first"

cat_by_name = {}
for c in cats:
    name = c["name"] if isinstance(c, dict) else str(c)
    slug = (c.get("slug") if isinstance(c, dict) else None) or name.lower().replace(" ", "-")
    row = db.query(Category).filter_by(name=name).first()
    if not row:
        row = Category(name=name, slug=slug)
        db.add(row)
        db.flush()
    cat_by_name[name] = row
db.commit()
print(f"categories ready: {sorted(cat_by_name)}")

made = updated = 0
for c in clips:
    cid = uuid.UUID(c["id"])
    row = db.get(Clip, cid)
    if row is None:
        row = Clip(id=cid)
        db.add(row)
        made += 1
    else:
        updated += 1

    row.title = c["title"]
    row.slug = c["slug"]
    row.editor_id = editor.id
    cat = cat_by_name.get(c.get("category"))
    row.category_id = cat.id if cat else None
    row.movie_name = c.get("movie_name")
    row.genre = c.get("genre")
    row.language = c.get("language") or "English"
    row.tags = c.get("tags") or []
    row.layers = c.get("layers") or []
    row.overlays = c.get("overlays")
    row.duration_sec = c.get("duration_sec")
    row.resolution = c.get("resolution") or "1080p"
    row.aspect_ratio = c.get("aspect_ratio") or "9:16"
    row.access = Access(c.get("access") or "free")
    row.status = ClipStatus(c.get("status") or "approved")
    row.is_featured = bool(c.get("is_featured"))
    row.downloads = int(c.get("downloads") or 0)
    row.review_note = c.get("review_note")
    row.thumb = c.get("thumb_key") or f"thumbs/{cid}.jpg"
    if not row.base_clip_path or row.base_clip_path == RAW_PLACEHOLDER:
        row.base_clip_path = c.get("raw_key") or RAW_PLACEHOLDER
    created = ts(c.get("created_at"))
    if created:
        row.created_at = created
        if row.status == ClipStatus.approved:
            row.published_at = created
    db.flush()  # one row per INSERT: client-side UUID PKs break insertmanyvalues sentinels

db.commit()

total = db.query(Clip).count()
approved = db.query(Clip).filter(Clip.status == ClipStatus.approved).count()
feat = db.query(Clip).filter(Clip.is_featured.is_(True)).count()
pending_raw = db.query(Clip).filter(Clip.base_clip_path == RAW_PLACEHOLDER).count()
print(f"clips: created={made} updated={updated} | db total={total} approved={approved} featured={feat}")
print(f"base_clip_path awaiting relink: {pending_raw}")
