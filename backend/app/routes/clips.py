"""Customer-facing catalog: browse/search/filter, detail, favorites, downloads."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models import Category, Clip, ClipStatus, Download, Favorite, User
from app.schemas.catalog import CategoryOut, ClipListOut, ClipOut, DownloadOut
from app.services.billing import assert_can_export
from app.services.catalog import SORTS, browse_query, clip_to_out
from app.services.storage import storage

router = APIRouter(tags=["catalog"])


@router.get("/categories", response_model=list[CategoryOut])
def list_categories(db: Session = Depends(get_db)) -> list[CategoryOut]:
    return [CategoryOut.model_validate(c) for c in db.scalars(select(Category).order_by(Category.name)).all()]


@router.get("/clips", response_model=ClipListOut)
def list_clips(
    db: Session = Depends(get_db),
    q: str | None = None,
    category: str | None = None,
    genre: str | None = None,
    language: str | None = None,
    access: str | None = None,
    featured: bool | None = None,
    sort: str = "trending",
    limit: int = Query(20, ge=1, le=60),
    offset: int = Query(0, ge=0),
) -> ClipListOut:
    if sort not in SORTS:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=f"sort must be one of {SORTS}")
    stmt = browse_query(
        db, q=q, category=category, genre=genre, language=language,
        access=access, featured=featured, sort=sort,
    )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(stmt.limit(limit).offset(offset)).all()
    return ClipListOut(items=[clip_to_out(c) for c in rows], total=total, limit=limit, offset=offset)


@router.get("/clips/{slug}", response_model=ClipOut)
def get_clip(slug: str, db: Session = Depends(get_db)) -> ClipOut:
    clip = db.scalar(select(Clip).where(Clip.slug == slug, Clip.status == ClipStatus.approved))
    if not clip:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Clip not found")
    return clip_to_out(clip)


def _approved_clip(db: Session, clip_id: uuid.UUID) -> Clip:
    clip = db.scalar(select(Clip).where(Clip.id == clip_id, Clip.status == ClipStatus.approved))
    if not clip:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Clip not found")
    return clip


@router.post("/clips/{clip_id}/favorite", status_code=status.HTTP_201_CREATED)
def add_favorite(clip_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    _approved_clip(db, clip_id)
    exists = db.scalar(select(Favorite).where(Favorite.user_id == user.id, Favorite.clip_id == clip_id))
    if not exists:
        db.add(Favorite(user_id=user.id, clip_id=clip_id))
        db.commit()
    return {"favorited": True}


@router.delete("/clips/{clip_id}/favorite")
def remove_favorite(clip_id: uuid.UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict:
    row = db.scalar(select(Favorite).where(Favorite.user_id == user.id, Favorite.clip_id == clip_id))
    if row:
        db.delete(row)
        db.commit()
    return {"favorited": False}


@router.get("/me/favorites", response_model=list[ClipOut])
def my_favorites(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[ClipOut]:
    stmt = select(Clip).join(Favorite, Favorite.clip_id == Clip.id).where(Favorite.user_id == user.id).order_by(Favorite.created_at.desc())
    return [clip_to_out(c) for c in db.scalars(stmt).all()]


@router.post("/clips/{clip_id}/download", status_code=status.HTTP_201_CREATED)
def record_download(
    clip_id: uuid.UUID,
    resolution: str = "1080p",
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    clip = _approved_clip(db, clip_id)
    assert_can_export(db, user, clip)  # Pro-access + monthly quota gate (§2, §11.3)
    db.add(Download(user_id=user.id, clip_id=clip_id, resolution=resolution))
    clip.downloads += 1
    db.commit()
    return {"recorded": True, "downloads": clip.downloads}


@router.post("/clips/{clip_id}/download-url")
def download_url(
    clip_id: uuid.UUID,
    resolution: str = "1080p",
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """Access-gated presigned GET URL for the base clip + records the export."""
    clip = _approved_clip(db, clip_id)
    assert_can_export(db, user, clip)
    if not clip.base_clip_path:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Clip has no uploaded file")
    db.add(Download(user_id=user.id, clip_id=clip_id, resolution=resolution))
    clip.downloads += 1
    db.commit()
    return {"url": storage.presign_download(clip.base_clip_path), "downloads": clip.downloads}


@router.get("/me/downloads", response_model=list[DownloadOut])
def my_downloads(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[DownloadOut]:
    rows = db.execute(
        select(Download, Clip.title).join(Clip, Clip.id == Download.clip_id)
        .where(Download.user_id == user.id).order_by(Download.created_at.desc())
    ).all()
    return [
        DownloadOut(id=d.id, clip_id=d.clip_id, clip_title=title, resolution=d.resolution, created_at=d.created_at)
        for d, title in rows
    ]
