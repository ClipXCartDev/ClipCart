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
from app.models import Category, Clip, ClipStatus, Payout, PayoutStatus, Plan, Role, User
from app.schemas.billing import PlanCreate, PlanOut, PlanUpdate
from app.schemas.catalog import CategoryCreate, CategoryOut, ClipOut, ReviewIn
from app.schemas.payout import PayoutOut
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


# --- Plans & pricing (§11.3) ---

@router.get("/plans", response_model=list[PlanOut])
def admin_list_plans(_: User = Depends(admin_only), db: Session = Depends(get_db)) -> list[PlanOut]:
    return [PlanOut.model_validate(p) for p in db.scalars(select(Plan).order_by(Plan.sort_order)).all()]


@router.post("/plans", response_model=PlanOut, status_code=status.HTTP_201_CREATED)
def create_plan(body: PlanCreate, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> PlanOut:
    slug = re.sub(r"[^a-z0-9]+", "-", body.name.lower()).strip("-")
    if db.scalar(select(Plan).where(Plan.slug == slug)):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Plan exists")
    plan = Plan(
        name=body.name, slug=slug, price_usd=body.price_usd, export_limit=body.export_limit,
        quality=body.quality, max_devices=body.max_devices, features=body.features, sort_order=body.sort_order,
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return PlanOut.model_validate(plan)


@router.put("/plans/{plan_id}", response_model=PlanOut)
def update_plan(plan_id: uuid.UUID, body: PlanUpdate, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> PlanOut:
    plan = db.get(Plan, plan_id)
    if not plan:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Plan not found")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(plan, k, v)
    db.commit()
    db.refresh(plan)
    return PlanOut.model_validate(plan)


# --- Editor payouts (§11.4) — manual settlement ---

def _payout_out(p: Payout, editor_name: str | None) -> PayoutOut:
    return PayoutOut(
        id=p.id, editor_id=p.editor_id, editor_name=editor_name, amount=float(p.amount),
        status=p.status.value, note=p.note, created_at=p.created_at, paid_at=p.paid_at,
    )


@router.get("/payouts", response_model=list[PayoutOut])
def list_payouts(status_filter: str | None = None, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> list[PayoutOut]:
    stmt = select(Payout, User.name).join(User, User.id == Payout.editor_id).order_by(Payout.created_at.desc())
    if status_filter:
        stmt = stmt.where(Payout.status == PayoutStatus(status_filter))
    return [_payout_out(p, name) for p, name in db.execute(stmt).all()]


def _get_pending_payout(db: Session, payout_id: uuid.UUID) -> Payout:
    p = db.get(Payout, payout_id)
    if not p:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Payout not found")
    if p.status != PayoutStatus.pending:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="Payout already processed")
    return p


@router.post("/payouts/{payout_id}/mark-paid", response_model=PayoutOut)
def mark_paid(payout_id: uuid.UUID, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> PayoutOut:
    p = _get_pending_payout(db, payout_id)
    p.status = PayoutStatus.paid
    p.paid_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(p)
    editor = db.get(User, p.editor_id)
    return _payout_out(p, editor.name if editor else None)


@router.post("/payouts/{payout_id}/reject", response_model=PayoutOut)
def reject_payout(payout_id: uuid.UUID, body: ReviewIn, _: User = Depends(admin_only), db: Session = Depends(get_db)) -> PayoutOut:
    p = _get_pending_payout(db, payout_id)
    p.status = PayoutStatus.rejected
    p.note = body.note
    db.commit()
    db.refresh(p)
    editor = db.get(User, p.editor_id)
    return _payout_out(p, editor.name if editor else None)
