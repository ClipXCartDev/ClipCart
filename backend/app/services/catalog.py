"""Catalog helpers: slug, serialization, browse query builder."""
from __future__ import annotations

import re
import uuid

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session

from app.models import Category, Clip, ClipStatus
from app.schemas.catalog import ClipOut
from app.services.storage import storage

SORTS = {"trending", "newest", "popular"}

_THUMB_TTL = 86400  # 24h — long enough that cached pages don't break


def _thumb_url(clip: Clip) -> str | None:
    """Presigned GET for the clip's poster frame. Key is deterministic (thumbs/{id}.jpg);
    the stored `thumb` column wins if present. Returns None when no base file exists."""
    key = clip.thumb or (f"thumbs/{clip.id}.jpg" if clip.base_clip_path else None)
    if not key:
        return None
    try:
        return storage.presign_download(key, expires=_THUMB_TTL)
    except Exception:
        return None


def _preview_url(clip: Clip) -> str | None:
    """Presigned GET for the 720p muted-preview (reels/web hover). Public-safe —
    viewing is free; the gate is on export/customization."""
    if not clip.base_clip_path:
        return None
    try:
        return storage.presign_download(f"previews/{clip.id}.mp4", expires=_THUMB_TTL)
    except Exception:
        return None


def slugify(title: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:40] or "clip"
    return f"{base}-{uuid.uuid4().hex[:6]}"


def clip_to_out(clip: Clip) -> ClipOut:
    return ClipOut(
        id=clip.id,
        title=clip.title,
        slug=clip.slug,
        editor_name=clip.editor.name if clip.editor else None,
        category=clip.category.name if clip.category else None,
        movie_name=clip.movie_name,
        genre=clip.genre,
        language=clip.language,
        tags=clip.tags or [],
        layers=clip.layers or [],
        duration_sec=clip.duration_sec,
        resolution=clip.resolution,
        aspect_ratio=clip.aspect_ratio,
        access=clip.access.value,
        status=clip.status.value,
        is_featured=clip.is_featured,
        downloads=clip.downloads,
        review_note=clip.review_note,
        thumb=_thumb_url(clip),
        preview=_preview_url(clip),
        created_at=clip.created_at,
    )


def browse_query(
    db: Session,
    *,
    q: str | None = None,
    category: str | None = None,
    genre: str | None = None,
    language: str | None = None,
    access: str | None = None,
    featured: bool | None = None,
    sort: str = "trending",
) -> Select:
    """Approved clips only, with filters + sort. Returns a Select of Clip."""
    stmt = select(Clip).where(Clip.status == ClipStatus.approved)

    if q:
        like = f"%{q.lower()}%"
        stmt = stmt.where(or_(func.lower(Clip.title).like(like), func.lower(Clip.movie_name).like(like)))
    if category:
        stmt = stmt.join(Category, Clip.category_id == Category.id).where(Category.slug == category)
    if genre:
        stmt = stmt.where(func.lower(Clip.genre) == genre.lower())
    if language:
        stmt = stmt.where(func.lower(Clip.language) == language.lower())
    if access:
        stmt = stmt.where(Clip.access == access)
    if featured is not None:
        stmt = stmt.where(Clip.is_featured == featured)

    if sort == "newest":
        stmt = stmt.order_by(Clip.created_at.desc())
    else:  # trending / popular
        stmt = stmt.order_by(Clip.downloads.desc(), Clip.created_at.desc())
    return stmt
