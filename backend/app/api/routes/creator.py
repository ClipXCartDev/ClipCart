"""Creator (editor) endpoints: upload clip, author template, track uploads."""
from __future__ import annotations

import re
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import require_role
from app.db.session import get_db
from app.models import Access, Clip, ClipStatus, Payout, PayoutStatus, Role, User
from app.schemas.catalog import ClipCreate, ClipOut, ClipUpdate, UploadUrlIn
from app.schemas.payout import EarningsOut, PayoutCreate, PayoutOut
from app.services.catalog import clip_to_out, slugify
from app.services.payouts import compute_earnings
from app.services.storage import storage

router = APIRouter(prefix="/creator", tags=["creator"])
editor_or_admin = require_role(Role.editor, Role.admin)


# M3: only real video clips may be uploaded — presign requires a whitelisted content type.
ALLOWED_UPLOAD_TYPES = {"video/mp4", "video/quicktime"}

# H3: base_clip_path must be a key the app itself minted via /upload-url, which always
# presigns under `clips/{uuid}/{filename}`. Reject anything that doesn't match that shape
# so an editor can't point a clip at an arbitrary object (another editor's key) in the bucket.
_BASE_CLIP_KEY_RE = re.compile(
    r"^clips/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,80}$"
)


def _validate_base_clip_path(path: str | None) -> None:
    if path is None:
        return
    if not _BASE_CLIP_KEY_RE.match(path):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "code": "invalid_base_clip_path",
                "message": "base_clip_path must be a key issued by /creator/upload-url (clips/{id}/{file}).",
            },
        )


@router.post("/upload-url")
def upload_url(body: UploadUrlIn, _: User = Depends(editor_or_admin)) -> dict:
    """Presigned PUT URL — editor uploads the base clip directly to storage (R2/local)."""
    if body.content_type not in ALLOWED_UPLOAD_TYPES:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "unsupported_type", "message": f"content_type must be one of {sorted(ALLOWED_UPLOAD_TYPES)}"},
        )
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", body.filename)[:80] or "clip.mp4"
    key = f"clips/{uuid.uuid4()}/{safe}"
    return storage.presign_upload(key, body.content_type)


@router.post("/clips", response_model=ClipOut, status_code=status.HTTP_201_CREATED)
def create_clip(body: ClipCreate, user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> ClipOut:
    _validate_base_clip_path(body.base_clip_path)
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
    if "base_clip_path" in data:
        _validate_base_clip_path(data["base_clip_path"])
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


# --- Earnings & payouts (§11.4) ---

@router.get("/earnings", response_model=EarningsOut)
def my_earnings(user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> EarningsOut:
    return EarningsOut(**compute_earnings(db, user))


@router.post("/payouts", response_model=PayoutOut, status_code=status.HTTP_201_CREATED)
def request_payout(body: PayoutCreate, user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> PayoutOut:
    # H4: lock this editor's existing payout rows so two concurrent requests can't both
    # read the same balance and both pass the check (double-spend). Postgres does the
    # real FOR UPDATE; SQLite (tests) ignores with_for_update, which is fine there.
    if db.bind is not None and db.bind.dialect.name == "postgresql":
        db.execute(
            select(Payout.id).where(Payout.editor_id == user.id).with_for_update()
        ).all()

    # Recompute available INSIDE the locked transaction.
    available = compute_earnings(db, user)["available"]
    if body.amount > available:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail={"code": "insufficient_balance", "available": available},
        )
    payout = Payout(editor_id=user.id, amount=body.amount, status=PayoutStatus.pending)
    db.add(payout)
    db.commit()
    db.refresh(payout)
    return PayoutOut(
        id=payout.id, editor_id=payout.editor_id, editor_name=user.name,
        amount=float(payout.amount), status=payout.status.value,
        note=payout.note, created_at=payout.created_at, paid_at=payout.paid_at,
    )


@router.get("/payouts", response_model=list[PayoutOut])
def my_payouts(user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> list[PayoutOut]:
    rows = db.scalars(select(Payout).where(Payout.editor_id == user.id).order_by(Payout.created_at.desc())).all()
    return [
        PayoutOut(
            id=p.id, editor_id=p.editor_id, editor_name=user.name, amount=float(p.amount),
            status=p.status.value, note=p.note, created_at=p.created_at, paid_at=p.paid_at,
        )
        for p in rows
    ]
