"""Catalog models: Category, Clip (template), Favorite, Download (decisions §11.5–11.7)."""
from __future__ import annotations

import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    JSON,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class Access(str, enum.Enum):
    free = "free"
    pro = "pro"


class ClipStatus(str, enum.Enum):
    pending = "pending"      # submitted, awaiting admin review
    approved = "approved"    # live in catalog
    rejected = "rejected"    # declined
    changes = "changes"      # changes requested


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(80), unique=True)
    slug: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Clip(Base):
    """A template = fixed base clip + admin-approved editable layers."""

    __tablename__ = "clips"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(140))
    slug: Mapped[str] = mapped_column(String(160), unique=True, index=True)
    editor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    category_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        ForeignKey("categories.id", ondelete="SET NULL"), nullable=True, index=True
    )

    # metadata (§11.5)
    movie_name: Mapped[Optional[str]] = mapped_column(String(140), nullable=True)
    genre: Mapped[Optional[str]] = mapped_column(String(60), nullable=True)
    language: Mapped[str] = mapped_column(String(40), default="English")
    tags: Mapped[list] = mapped_column(JSON, default=list)
    duration_sec: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    resolution: Mapped[str] = mapped_column(String(16), default="1080p")
    aspect_ratio: Mapped[str] = mapped_column(String(12), default="9:16")

    # customizable layers the customer may edit (§11.7)
    layers: Mapped[list] = mapped_column(JSON, default=list)
    # creator-authored overlays (subtitles/logo/text) pre-rendered over the raw
    # video in the editor — NOT burned until the customer exports. Snapshot-format
    # JSON matching the app's EditorProject.snapshot(): {subs:[...], logoUrl, logoDx,...}.
    overlays: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

    access: Mapped[Access] = mapped_column(Enum(Access), default=Access.free, index=True)
    status: Mapped[ClipStatus] = mapped_column(Enum(ClipStatus), default=ClipStatus.pending, index=True)
    is_featured: Mapped[bool] = mapped_column(default=False, index=True)
    downloads: Mapped[int] = mapped_column(Integer, default=0)
    review_note: Mapped[Optional[str]] = mapped_column(String(400), nullable=True)

    base_clip_path: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    thumb: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)

    editor = relationship("User")
    category = relationship("Category")


class Favorite(Base):
    __tablename__ = "favorites"
    __table_args__ = (UniqueConstraint("user_id", "clip_id", name="uq_user_clip_fav"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    clip_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clips.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Download(Base):
    """Download/export history (§11.6)."""

    __tablename__ = "downloads"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    clip_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("clips.id", ondelete="CASCADE"), index=True)
    resolution: Mapped[str] = mapped_column(String(16), default="1080p")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
