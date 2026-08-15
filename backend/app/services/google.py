"""Google Sign-In verification.

Production verifies the ID token signature against Google's certs via google-auth.
The verifier is a module-level callable so tests can monkeypatch it without network.
"""
from __future__ import annotations

from dataclasses import dataclass

from app.core.config import settings


@dataclass
class GoogleIdentity:
    sub: str
    email: str
    name: str


class GoogleAuthError(Exception):
    pass


def verify_google_token(id_token: str) -> GoogleIdentity:
    """Verify a Google ID token and return the identity. Raises GoogleAuthError."""
    try:
        from google.auth.transport import requests as google_requests
        from google.oauth2 import id_token as google_id_token
    except ImportError as exc:  # pragma: no cover
        raise GoogleAuthError("google-auth not installed") from exc

    try:
        info = google_id_token.verify_oauth2_token(
            id_token,
            google_requests.Request(),
            settings.GOOGLE_CLIENT_ID or None,
        )
    except Exception as exc:  # noqa: BLE001 - normalise to our error type
        try:  # TEMP diagnostic
            import base64
            import json
            seg = id_token.split(".")[1]
            seg += "=" * (-len(seg) % 4)
            claims = json.loads(base64.urlsafe_b64decode(seg))
            print(f"GOOGLE_VERIFY_FAIL aud={claims.get('aud')} iss={claims.get('iss')} "
                  f"azp={claims.get('azp')} expected={settings.GOOGLE_CLIENT_ID} err={exc}", flush=True)
        except Exception:  # pragma: no cover
            print(f"GOOGLE_VERIFY_FAIL (no-decode) err={exc}", flush=True)
        raise GoogleAuthError(str(exc)) from exc

    print(f"GOOGLE_VERIFY_OK email={info.get('email')} email_verified={info.get('email_verified')!r} aud={info.get('aud')}", flush=True)
    if not info.get("email_verified", False):
        raise GoogleAuthError("email not verified by Google")

    return GoogleIdentity(
        sub=info["sub"],
        email=info["email"],
        name=info.get("name") or info["email"].split("@")[0],
    )
