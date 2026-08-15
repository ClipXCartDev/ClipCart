"""Catalog schemas."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class CategoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    name: str
    slug: str


class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class ClipOut(BaseModel):
    id: uuid.UUID
    title: str
    slug: str
    editor_name: str | None = None
    category: str | None = None
    movie_name: str | None = None
    genre: str | None = None
    language: str
    tags: list = []
    layers: list = []
    duration_sec: int | None = None
    resolution: str
    aspect_ratio: str
    access: str
    status: str
    is_featured: bool
    downloads: int
    review_note: str | None = None
    thumb: str | None = None
    preview: str | None = None
    created_at: datetime


class ClipListOut(BaseModel):
    items: list[ClipOut]
    total: int
    limit: int
    offset: int


class ClipCreate(BaseModel):
    title: str = Field(min_length=1, max_length=140)
    category_id: uuid.UUID | None = None
    movie_name: str | None = None
    genre: str | None = None
    language: str = "English"
    tags: list[str] = []
    layers: list[str] = []
    duration_sec: int | None = None
    resolution: str = "1080p"
    aspect_ratio: str = "9:16"
    access: str = "free"
    base_clip_path: str | None = None
    thumb: str | None = None


class ClipUpdate(BaseModel):
    title: str | None = None
    category_id: uuid.UUID | None = None
    movie_name: str | None = None
    genre: str | None = None
    language: str | None = None
    tags: list[str] | None = None
    layers: list[str] | None = None
    duration_sec: int | None = None
    resolution: str | None = None
    aspect_ratio: str | None = None
    access: str | None = None


class ReviewIn(BaseModel):
    note: str | None = Field(default=None, max_length=400)


class DownloadOut(BaseModel):
    id: uuid.UUID
    clip_id: uuid.UUID
    clip_title: str
    resolution: str
    created_at: datetime


class UploadUrlIn(BaseModel):
    filename: str = Field(min_length=1, max_length=120)
    content_type: str | None = None
