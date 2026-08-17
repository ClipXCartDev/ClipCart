"""Application settings — all secrets/config via environment variables (no hardcoding)."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    PROJECT_NAME: str = "ClipCart API"
    ENV: str = "dev"

    # Database — Postgres in prod (compose), sqlite fallback for local/dev + tests.
    DATABASE_URL: str = "sqlite:///./clipcart.db"

    # Auth / JWT
    JWT_SECRET: str = "change-me-in-prod"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Device binding (decisions §7.1)
    MAX_DEVICES: int = 2

    # Google Sign-In
    GOOGLE_CLIENT_ID: str = ""

    # Binance Pay (decisions §2) — crypto-only payment
    BINANCE_PAY_KEY: str = ""
    BINANCE_PAY_SECRET: str = ""
    BINANCE_PAY_BASE_URL: str = "https://bpay.binanceapi.com"
    SUBSCRIPTION_DAYS: int = 30

    # Editor payouts (decisions §11.4) — rate per download (business placeholder).
    PAYOUT_RATE_PER_DOWNLOAD: float = 0.02

    # Storage — clip/video assets. "local" (dev/tests) or "r2" (Cloudflare R2).
    STORAGE_PROVIDER: str = "local"
    STORAGE_DIR: str = "./storage"
    STORAGE_URL_SECRET: str = "change-me-storage-secret"
    PRESIGN_EXPIRE_SECONDS: int = 3600
    R2_ACCOUNT_ID: str = ""
    R2_ACCESS_KEY_ID: str = ""
    R2_SECRET_ACCESS_KEY: str = ""
    R2_BUCKET: str = "clipcart"

    # CORS — allowed web/admin origins ("*" for dev, comma-separated for prod).
    CORS_ORIGINS: str = "*"

    # App store links — surfaced on web so users know editing happens in the apps.
    # Customisable from backend via env (no redeploy of the web needed).
    IOS_APP_URL: str = ""      # App Store link (empty → "coming soon")
    ANDROID_APP_URL: str = ""  # Play Store link
    APK_DIRECT_URL: str = "https://clipscart.app/downloads"  # sideload / direct APK


settings = Settings()

# Fail fast in non-dev if security-critical secrets are still the insecure defaults
# (a default JWT secret lets anyone forge tokens / impersonate any user).
if settings.ENV != "dev":
    _bad = []
    if settings.JWT_SECRET in ("", "change-me-in-prod"):
        _bad.append("JWT_SECRET")
    # storage HMAC secret only matters for the local-signing provider (R2 signs its own)
    if settings.STORAGE_PROVIDER == "local" and settings.STORAGE_URL_SECRET in ("", "change-me-storage-secret"):
        _bad.append("STORAGE_URL_SECRET")
    if _bad:
        raise RuntimeError(f"Insecure default secret(s) in prod: {', '.join(_bad)}. Set strong env values.")
