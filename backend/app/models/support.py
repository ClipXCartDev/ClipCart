"""Support chat: a lightweight in-app conversation between a customer and CS.

Deliberately minimal (one thread per user + a flat message list) per the lean
budget — no websockets, no third-party widget. The app polls for new messages.
"""
from __future__ import annotations

import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, String, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


class Sender(str, enum.Enum):
    user = "user"
    support = "support"


class SupportThread(Base):
    """One conversation per user. Created on the user's first message."""

    __tablename__ = "support_threads"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    # closed threads are hidden from the admin's open queue but still readable.
    closed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    messages: Mapped[list["SupportMessage"]] = relationship(
        back_populates="thread", cascade="all, delete-orphan", order_by="SupportMessage.created_at"
    )


class SupportMessage(Base):
    __tablename__ = "support_messages"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    thread_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("support_threads.id", ondelete="CASCADE"), index=True
    )
    sender: Mapped[Sender] = mapped_column(Enum(Sender), nullable=False)
    # the admin/agent id who replied (null for user messages)
    agent_id: Mapped[Optional[uuid.UUID]] = mapped_column(Uuid, nullable=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    read_by_user: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )

    thread: Mapped["SupportThread"] = relationship(back_populates="messages")
