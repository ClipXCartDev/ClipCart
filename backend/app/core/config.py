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


settings = Settings()
