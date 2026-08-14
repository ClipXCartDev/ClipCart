"""Asset storage: Cloudflare R2 (prod) or local disk (dev/tests).

Editors get a presigned PUT URL to upload the base clip directly; customers get a
short-lived presigned GET URL to download (decisions §6.3 — temporary signed URLs for
premium assets). Local mode signs its own /storage/{key} endpoint with an HMAC token so
the whole flow is testable without R2 credentials.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import time

from app.core.config import settings


class Storage:
    def presign_upload(self, key: str, content_type: str | None = None) -> dict:
        raise NotImplementedError

    def presign_download(self, key: str, expires: int | None = None) -> str:
        raise NotImplementedError


class LocalStorage(Storage):
    def _token(self, key: str, method: str, exp: int) -> str:
        msg = f"{method}:{key}:{exp}".encode()
        return hmac.new(settings.STORAGE_URL_SECRET.encode(), msg, hashlib.sha256).hexdigest()

    def presign_upload(self, key: str, content_type: str | None = None) -> dict:
        exp = int(time.time()) + settings.PRESIGN_EXPIRE_SECONDS
        token = self._token(key, "PUT", exp)
        return {"url": f"/api/v1/storage/{key}?exp={exp}&token={token}", "method": "PUT", "key": key}

    def presign_download(self, key: str, expires: int | None = None) -> str:
        exp = int(time.time()) + (expires or settings.PRESIGN_EXPIRE_SECONDS)
        token = self._token(key, "GET", exp)
        return f"/api/v1/storage/{key}?exp={exp}&token={token}"

    def verify(self, key: str, method: str, exp: int, token: str) -> bool:
        if int(exp) < time.time():
            return False
        return hmac.compare_digest(self._token(key, method, int(exp)), token)

    def path(self, key: str) -> str:
        return os.path.join(settings.STORAGE_DIR, key)


class R2Storage(Storage):
    def __init__(self) -> None:
        import boto3

        self.bucket = settings.R2_BUCKET
        self.client = boto3.client(
            "s3",
            endpoint_url=f"https://{settings.R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
            aws_access_key_id=settings.R2_ACCESS_KEY_ID,
            aws_secret_access_key=settings.R2_SECRET_ACCESS_KEY,
            region_name="auto",
        )

    def presign_upload(self, key: str, content_type: str | None = None) -> dict:
        params = {"Bucket": self.bucket, "Key": key}
        if content_type:
            params["ContentType"] = content_type
        url = self.client.generate_presigned_url("put_object", Params=params, ExpiresIn=settings.PRESIGN_EXPIRE_SECONDS)
        return {"url": url, "method": "PUT", "key": key}

    def presign_download(self, key: str, expires: int | None = None) -> str:
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=expires or settings.PRESIGN_EXPIRE_SECONDS,
        )


def _build() -> Storage:
    return R2Storage() if settings.STORAGE_PROVIDER == "r2" else LocalStorage()


storage: Storage = _build()
