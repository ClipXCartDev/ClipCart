"""Local storage endpoints (dev/tests) — HMAC-signed PUT/GET. Inactive in R2 mode."""
from __future__ import annotations

import os

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import FileResponse

from app.services.storage import LocalStorage, storage

router = APIRouter(prefix="/storage", tags=["storage"])


def _local() -> LocalStorage:
    if not isinstance(storage, LocalStorage):
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    return storage


@router.put("/{key:path}")
async def put_object(key: str, exp: int, token: str, request: Request) -> dict:
    s = _local()
    if not s.verify(key, "PUT", exp, token):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Bad or expired token")
    path = s.path(key)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(await request.body())
    return {"ok": True, "key": key}


@router.get("/{key:path}")
def get_object(key: str, exp: int, token: str) -> FileResponse:
    s = _local()
    if not s.verify(key, "GET", exp, token):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Bad or expired token")
    path = s.path(key)
    if not os.path.exists(path):
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Not found")
    return FileResponse(path)
