"""Admin: approval workflow, feature clips, manage categories."""
from __future__ import annotations

import re
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import require_role
from app.db.session import get_db
from app.models import Category, Clip, ClipStatus, Role, User
from app.schemas.catalog import CategoryCreate, CategoryOut, ClipOut, ReviewIn
from app.services.catalog import clip_to_out

router = APIRouter(prefix="/admin", tags=["admin"])
admin_only = require_role(Role.admin)


def _get_clip(db: Session, clip_id: uuid.UUID) -> Clip:
    clip = db.get(Clip, clip_id)
    if not clip:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Clip not found")
    return clip


@router.get("/clips", response_model=list[ClipOut])
def admin_list_clips(status_filter: str | None = None, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> list[ClipOut]:
    stmt = select(Clip).order_by(Clip.created_at.desc())
    if status_filter:
        stmt = stmt.where(Clip.status == ClipStatus(status_filter))
    return [clip_to_out(c) for c in db.scalars(stmt).all()]


@router.post("/clips/{clip_id}/approve", response_model=ClipOut)
def approve(clip_id: uuid.UUID, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> ClipOut:
    clip = _get_clip(db, clip_id)
    clip.status = ClipStatus.approved
    clip.review_note = None
    clip.published_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(clip)
    return clip_to_out(clip)


@router.post("/clips/{clip_id}/reject", response_model=ClipOut)
def reject(clip_id: uuid.UUID, body: ReviewIn, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> ClipOut:
    clip = _get_clip(db, clip_id)
    clip.status = ClipStatus.rejected
    clip.review_note = body.note
    db.commit()
    db.refresh(clip)
    return clip_to_out(clip)


@router.post("/clips/{clip_id}/request-changes", response_model=ClipOut)
def request_changes(clip_id: uuid.UUID, body: ReviewIn, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> ClipOut:
    clip = _get_clip(db, clip_id)
    clip.status = ClipStatus.changes
    clip.review_note = body.note
    db.commit()
    db.refresh(clip)
    return clip_to_out(clip)


@router.post("/clips/{clip_id}/feature", response_model=ClipOut)
def toggle_feature(clip_id: uuid.UUID, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> ClipOut:
    clip = _get_clip(db, clip_id)
    if clip.status != ClipStatus.approved:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Only approved clips can be featured")
    clip.is_featured = not clip.is_featured
    db.commit()
    db.refresh(clip)
    return clip_to_out(clip)


@router.post("/categories", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(body: CategoryCreate, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> CategoryOut:
    slug = re.sub(r"[^a-z0-9]+", "-", body.name.lower()).strip("-")
    if db.scalar(select(Category).where(Category.slug == slug)):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Category exists")
    cat = Category(name=body.name, slug=slug)
    db.add(cat)
    db.commit()
    db.refresh(cat)
    return CategoryOut.model_validate(cat)
