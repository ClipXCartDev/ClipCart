"""Creator (editor) endpoints: upload clip, author template, track uploads."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import require_role
from app.db.session import get_db
from app.models import Access, Clip, ClipStatus, Role, User
from app.schemas.catalog import ClipCreate, ClipOut, ClipUpdate
from app.services.catalog import clip_to_out, slugify

router = APIRouter(prefix="/creator", tags=["creator"])
editor_or_admin = require_role(Role.editor, Role.admin)


@router.post("/clips", response_model=ClipOut, status_code=status.HTTP_201_CREATED)
def create_clip(body: ClipCreate, user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> ClipOut:
    clip = Clip(
        title=body.title,
        slug=slugify(body.title),
        editor_id=user.id,
        category_id=body.category_id,
        movie_name=body.movie_name,
        genre=body.genre,
        language=body.language,
        tags=body.tags,
        layers=body.layers,
        duration_sec=body.duration_sec,
        resolution=body.resolution,
        aspect_ratio=body.aspect_ratio,
        access=Access(body.access),
        base_clip_path=body.base_clip_path,
        thumb=body.thumb,
        status=ClipStatus.pending,
    )
    db.add(clip)
    db.commit()
    db.refresh(clip)
    return clip_to_out(clip)


def _own_editable(db: Session, clip_id: uuid.UUID, user: User) -> Clip:
    clip = db.scalar(select(Clip).where(Clip.id == clip_id, Clip.editor_id == user.id))
    if not clip:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Clip not found")
    if clip.status == ClipStatus.approved:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Approved clips can't be edited")
    return clip


@router.put("/clips/{clip_id}", response_model=ClipOut)
def update_clip(clip_id: uuid.UUID, body: ClipUpdate, user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> ClipOut:
    clip = _own_editable(db, clip_id, user)
    data = body.model_dump(exclude_unset=True)
    if "access" in data:
        data["access"] = Access(data["access"])
    for k, v in data.items():
        setattr(clip, k, v)
    db.commit()
    db.refresh(clip)
    return clip_to_out(clip)


@router.post("/clips/{clip_id}/submit", response_model=ClipOut)
def submit_clip(clip_id: uuid.UUID, user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> ClipOut:
    """Resubmit after 'changes' back into the review queue."""
    clip = db.scalar(select(Clip).where(Clip.id == clip_id, Clip.editor_id == user.id))
    if not clip:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Clip not found")
    if clip.status not in (ClipStatus.changes, ClipStatus.rejected):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Only clips needing changes can be resubmitted")
    clip.status = ClipStatus.pending
    clip.review_note = None
    db.commit()
    db.refresh(clip)
    return clip_to_out(clip)


@router.get("/clips", response_model=list[ClipOut])
def my_uploads(user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> list[ClipOut]:
    rows = db.scalars(select(Clip).where(Clip.editor_id == user.id).order_by(Clip.created_at.desc())).all()
    return [clip_to_out(c) for c in rows]
