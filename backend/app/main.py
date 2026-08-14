"""ClipCart FastAPI application entrypoint."""
from fastapi import FastAPI

from app.api.routes import api_router
from app.core.config import settings
from app.db.base import Base
from app.db.session import engine

# v1: create tables on boot. Migrations (Alembic) added in a later sprint.
import app.models  # noqa: F401  (register models on Base metadata)

Base.metadata.create_all(bind=engine)

app = FastAPI(title=settings.PROJECT_NAME)


@app.get("/health", tags=["system"])
def health() -> dict:
    return {"status": "ok", "env": settings.ENV}


app.include_router(api_router, prefix="/api/v1")
