"""Payout logic: compute editor earnings from downloads minus committed payouts."""
from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Clip, Download, Payout, PayoutStatus, User


def compute_earnings(db: Session, editor: User) -> dict:
    rate = settings.PAYOUT_RATE_PER_DOWNLOAD

    # M5: an editor must NOT earn payouts by downloading their own clips — exclude
    # self-downloads (downloader == clip owner) from the earning count.
    downloads = db.scalar(
        select(func.count())
        .select_from(Download)
        .join(Clip, Clip.id == Download.clip_id)
        .where(Clip.editor_id == editor.id, Download.user_id != editor.id)
    ) or 0
    earned = round(downloads * rate, 2)

    def _sum(status: PayoutStatus) -> float:
        val = db.scalar(
            select(func.coalesce(func.sum(Payout.amount), 0)).where(
                Payout.editor_id == editor.id, Payout.status == status
            )
        )
        return float(val or 0)

    pending = _sum(PayoutStatus.pending)
    paid = _sum(PayoutStatus.paid)
    available = round(earned - pending - paid, 2)
    return {
        "downloads": downloads,
        "rate": rate,
        "earned": earned,
        "pending": round(pending, 2),
        "paid": round(paid, 2),
        "available": available,
    }
