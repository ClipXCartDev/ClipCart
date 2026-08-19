"""In-app support chat.

Customer side: read my conversation, send a message, mark support replies read.
Admin/CS side: list open threads, read one, reply, close.

Lean by design (decisions): a flat message list the app polls — no websockets,
no external chat service. One thread per user.
"""
from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_role
from app.db.session import get_db
from app.models import Role, Sender, SupportMessage, SupportThread, User

router = APIRouter(prefix="/support", tags=["support"])


# ---------- schemas ----------
class MessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=4000)


class MessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    sender: Sender
    body: str
    created_at: datetime


class ThreadOut(BaseModel):
    id: uuid.UUID
    closed: bool
    messages: list[MessageOut]
    unread_for_user: int


class AdminThreadOut(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    user_name: str
    user_email: str
    closed: bool
    updated_at: datetime
    last_message: str | None
    unread_for_agent: int


def _get_or_create_thread(db: Session, user: User) -> SupportThread:
    thread = db.scalar(select(SupportThread).where(SupportThread.user_id == user.id))
    if thread is None:
        thread = SupportThread(user_id=user.id)
        db.add(thread)
        db.commit()
        db.refresh(thread)
    return thread


# ---------- customer ----------
@router.get("/thread", response_model=ThreadOut)
def my_thread(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> ThreadOut:
    thread = _get_or_create_thread(db, user)
    unread = sum(1 for m in thread.messages if m.sender == Sender.support and not m.read_by_user)
    return ThreadOut(
        id=thread.id,
        closed=thread.closed,
        messages=[MessageOut.model_validate(m) for m in thread.messages],
        unread_for_user=unread,
    )


@router.post("/thread/messages", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
def send_message(
    body: MessageIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> MessageOut:
    thread = _get_or_create_thread(db, user)
    msg = SupportMessage(thread_id=thread.id, sender=Sender.user, body=body.body.strip())
    thread.closed = False  # a new user message reopens a closed thread
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return MessageOut.model_validate(msg)


@router.post("/thread/read")
def mark_read(
    user: User = Depends(get_current_user), db: Session = Depends(get_db)
) -> dict:
    thread = db.scalar(select(SupportThread).where(SupportThread.user_id == user.id))
    if thread:
        for m in thread.messages:
            if m.sender == Sender.support and not m.read_by_user:
                m.read_by_user = True
        db.commit()
    return {"ok": True}


# ---------- admin / CS agent ----------
@router.get("/admin/threads", response_model=list[AdminThreadOut])
def list_threads(
    include_closed: bool = False,
    _: User = Depends(require_role(Role.admin)),
    db: Session = Depends(get_db),
) -> list[AdminThreadOut]:
    stmt = select(SupportThread).order_by(SupportThread.updated_at.desc())
    if not include_closed:
        stmt = stmt.where(SupportThread.closed == False)  # noqa: E712
    threads = db.scalars(stmt).all()
    out: list[AdminThreadOut] = []
    for t in threads:
        u = db.get(User, t.user_id)
        last = t.messages[-1].body if t.messages else None
        unread = sum(1 for m in t.messages if m.sender == Sender.user)
        out.append(
            AdminThreadOut(
                id=t.id,
                user_id=t.user_id,
                user_name=u.name if u else "—",
                user_email=u.email if u else "—",
                closed=t.closed,
                updated_at=t.updated_at,
                last_message=last,
                unread_for_agent=unread,
            )
        )
    return out


@router.get("/admin/threads/{thread_id}", response_model=ThreadOut)
def read_thread(
    thread_id: uuid.UUID,
    _: User = Depends(require_role(Role.admin)),
    db: Session = Depends(get_db),
) -> ThreadOut:
    thread = db.get(SupportThread, thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")
    return ThreadOut(
        id=thread.id,
        closed=thread.closed,
        messages=[MessageOut.model_validate(m) for m in thread.messages],
        unread_for_user=0,
    )


@router.post("/admin/threads/{thread_id}/reply", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
def reply(
    thread_id: uuid.UUID,
    body: MessageIn,
    agent: User = Depends(require_role(Role.admin)),
    db: Session = Depends(get_db),
) -> MessageOut:
    thread = db.get(SupportThread, thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")
    msg = SupportMessage(
        thread_id=thread.id, sender=Sender.support, agent_id=agent.id, body=body.body.strip()
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return MessageOut.model_validate(msg)


@router.post("/admin/threads/{thread_id}/close")
def close_thread(
    thread_id: uuid.UUID,
    _: User = Depends(require_role(Role.admin)),
    db: Session = Depends(get_db),
) -> dict:
    thread = db.get(SupportThread, thread_id)
    if thread is None:
        raise HTTPException(status_code=404, detail="Thread not found")
    thread.closed = True
    db.commit()
    return {"ok": True}
