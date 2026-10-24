"""Settings the app reads at runtime.

Public on purpose: these are the caption looks the editor offers, not anything
about an account. Requiring a token would mean the editor could not draw its
own preset row until sign-in had finished, for no protection at all.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.services import presets as preset_service

router = APIRouter(prefix="/config", tags=["config"])


@router.get("/caption-presets")
def caption_presets(db: Session = Depends(get_db)) -> dict:
    return {"presets": preset_service.get(db)}
