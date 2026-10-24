"""Settings an admin can change without a release.

One table, one row per setting, each holding a JSON document. It exists because
the caption presets - what a customer's captions can look like in one tap - are
a product decision, and a product decision that needs an app build to change is
one nobody makes.

Deliberately a key/value table rather than a column per setting: the alternative
is a migration every time somebody wants another knob, and there is no migration
tool here.
"""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import JSON

from app.db.base import Base

# JSONB on Postgres, plain JSON on the SQLite the tests run against.
_Json = JSON().with_variant(JSONB(), "postgresql")


class AppSetting(Base):
    __tablename__ = "app_settings"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[dict] = mapped_column(_Json, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


#: The key the caption presets live under.
CAPTION_PRESETS = "caption_presets"
