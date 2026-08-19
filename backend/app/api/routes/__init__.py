from fastapi import APIRouter

from app.api.routes import admin, auth, billing, clips, creator, storage, support

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(clips.router)
api_router.include_router(creator.router)
api_router.include_router(billing.router)
api_router.include_router(storage.router)
api_router.include_router(admin.router)
api_router.include_router(support.router)
