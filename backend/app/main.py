"""ClipCart FastAPI application entrypoint."""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import api_router
from app.core.config import settings
from app.db import bootstrap
from app.db.base import Base
from app.db.session import engine

# v1: create tables on boot. Migrations (Alembic) added in a later sprint.
import app.models  # noqa: F401  (register models on Base metadata)

Base.metadata.create_all(bind=engine)
# create_all makes missing tables but never alters an existing one, so columns
# added to a model after a deploy have to be put on by hand. Idempotent.
bootstrap.run()

app = FastAPI(title=settings.PROJECT_NAME)

_origins = ["*"] if settings.CORS_ORIGINS.strip() == "*" else [o.strip() for o in settings.CORS_ORIGINS.split(",")]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=False,  # Bearer tokens, not cookies
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", tags=["system"])
def health() -> dict:
    return {"status": "ok", "env": settings.ENV}


app.include_router(api_router, prefix="/api/v1")
