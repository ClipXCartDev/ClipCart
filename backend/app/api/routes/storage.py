"""Local storage endpoints (dev/tests) — HMAC-signed PUT/GET. Inactive in R2 mode."""
from __future__ import annotations

import os

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import FileResponse

from app.services.storage import LocalStorage, storage

router = APIRouter(prefix="/storage", tags=["storage"])

# M3: cap uploaded body size to prevent memory/disk exhaustion (200MB).
MAX_UPLOAD_BYTES = 200 * 1024 * 1024


def _local() -> LocalStorage:
    if not isinstance(storage, LocalStorage):
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    return storage


@router.put("/{key:path}")
async def put_object(key: str, exp: int, token: str, request: Request) -> dict:
    s = _local()
    if not s.verify(key, "PUT", exp, token):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Bad or expired token")

    # M3: reject oversized uploads before buffering the whole body in memory.
    clen = request.headers.get("content-length")
    if clen is not None:
        try:
            if int(clen) > MAX_UPLOAD_BYTES:
                raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Upload too large")
        except ValueError:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Bad Content-Length")

    body = await request.body()
    if len(body) > MAX_UPLOAD_BYTES:  # guards chunked uploads with no Content-Length
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Upload too large")

    path = s.path(key)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(body)
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
