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
from app.services.subtitles import SubtitleError
from app.services.subtitles import parse as parse_subtitles
from app.services.storage import storage

router = APIRouter(prefix="/creator", tags=["creator"])
editor_or_admin = require_role(Role.editor, Role.admin)


# M3: only real video clips may be uploaded — presign requires a whitelisted content type.
ALLOWED_UPLOAD_TYPES = {"video/mp4", "video/quicktime"}

# A creator's own mark, which travels with the clip and is drawn on every
# customer's copy. Kept to the lossless formats, because a mark is a logo and a
# JPEG logo has a grey box around it.
ALLOWED_MARK_TYPES = {"image/png", "image/webp"}

#: Where a mark is stored. Separate from clips/ so the base-clip guard and this
#: one cannot be used to reach each other's objects.
_MARK_KEY_RE = re.compile(r"^marks/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,80}$")

# H3: base_clip_path must be a key the app itself minted via /upload-url, which always
# presigns under `clips/{uuid}/{filename}`. Reject anything that doesn't match that shape
# so an editor can't point a clip at an arbitrary object (another editor's key) in the bucket.
_BASE_CLIP_KEY_RE = re.compile(
    r"^clips/[0-9a-fA-F-]{36}/[A-Za-z0-9._-]{1,80}$"
)


def _clean_overlays(overlays: dict | None) -> dict | None:
    """What a creator may put in a clip's authored layers.

    `logoUrl` is dropped and `logoKey` is checked, because the customer's app
    downloads whatever that field names onto their phone. Left open, an
    approved clip could point every customer at any URL on the internet; and a
    presigned URL stored at upload time would have expired long before anyone
    opened the clip anyway. The key is signed fresh on the way out instead.
    """
    if overlays is None:
        return None
    if not isinstance(overlays, dict):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "invalid_overlays", "message": "overlays must be an object."},
        )
    clean = {k: v for k, v in overlays.items() if k not in ("logoUrl", "logo_url", "logoPath")}
    key = clean.get("logoKey")
    if key is not None:
        if not isinstance(key, str) or not _MARK_KEY_RE.match(key):
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={
                    "code": "invalid_mark_key",
                    "message": "logoKey must be a key issued by /creator/upload-url (marks/{id}/{file}).",
                },
            )
    return clean


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
    """Presigned PUT URL — the editor uploads straight to storage (R2/local).

    Two kinds of object go through here: the base clip, and the creator's own
    mark. They are kept under different prefixes so the key guards on each
    cannot be used to reach the other's objects.
    """
    if body.content_type in ALLOWED_MARK_TYPES:
        safe = re.sub(r"[^A-Za-z0-9._-]", "_", body.filename)[:80] or "mark.png"
        return storage.presign_upload(f"marks/{uuid.uuid4()}/{safe}", body.content_type)
    if body.content_type not in ALLOWED_UPLOAD_TYPES:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "code": "unsupported_type",
                "message": "content_type must be one of "
                + f"{sorted(ALLOWED_UPLOAD_TYPES | ALLOWED_MARK_TYPES)}",
            },
        )
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", body.filename)[:80] or "clip.mp4"
    key = f"clips/{uuid.uuid4()}/{safe}"
    return storage.presign_upload(key, body.content_type)


@router.post("/subtitles/parse")
def parse_subtitle_file(body: dict, _: User = Depends(editor_or_admin)) -> dict:
    """Caption layers from an .srt or .vtt the creator already has.

    Server-side because there are two creator clients and one correct answer:
    the app and the web must produce identical layers from identical files, and
    a subtitle parser is exactly the kind of thing that drifts when written
    twice. The reply drops straight into a clip's `overlays.subs`.
    """
    text = body.get("text")
    if not isinstance(text, str):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "no_text", "message": "Send the subtitle file's text as `text`."},
        )
    if len(text) > 1_000_000:
        raise HTTPException(
            status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={"code": "too_large", "message": "That subtitle file is too big."},
        )
    raw_duration = body.get("duration")
    duration = float(raw_duration) if isinstance(raw_duration, (int, float)) else None
    try:
        captions = parse_subtitles(text, duration=duration)
    except SubtitleError as e:
        # The message names what was expected; it is written to be shown.
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"code": "unreadable_subtitles", "message": str(e)},
        )
    return {"captions": captions, "count": len(captions)}


@router.post("/clips", response_model=ClipOut, status_code=status.HTTP_201_CREATED)
def create_clip(body: ClipCreate, user: User = Depends(editor_or_admin), db: Session = Depends(get_db)) -> ClipOut:
    _validate_base_clip_path(body.base_clip_path)
    overlays = _clean_overlays(body.overlays)
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
        overlays=overlays,
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
        if data["base_clip_path"] != clip.base_clip_path:
            # the preview and poster belong to the file that was replaced
            clip.media_status = "pending"
            clip.media_error = None
            clip.media_attempts = 0
            clip.media_claimed_at = None
    if "overlays" in data:
        data["overlays"] = _clean_overlays(data["overlays"])
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
