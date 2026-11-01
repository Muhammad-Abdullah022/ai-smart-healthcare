"""Entry point of the backend.

Run locally with:
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
Then open http://localhost:8000/docs to try the API.
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.core.errors import register_error_handlers
from app.db.mongo import create_client, ensure_indexes
from app.routers import assessments, auth, profile


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    client = None
    # Tests put a fake database on app.state before starting, so we skip connecting.
    if not hasattr(app.state, "db"):
        if settings.use_memory_db:
            # Development only: an in-memory database, emptied on every restart.
            from mongomock_motor import AsyncMongoMockClient

            print("WARNING: USE_MEMORY_DB=true -> data is NOT saved. Use MongoDB Atlas for real data.")
            app.state.db = AsyncMongoMockClient(tz_aware=True)[settings.mongodb_db]
        elif not settings.mongodb_uri:
            raise RuntimeError("Set MONGODB_URI in backend/.env, or USE_MEMORY_DB=true for a quick local test.")
        else:
            client = create_client(settings.mongodb_uri)
            app.state.db = client[settings.mongodb_db]
    await ensure_indexes(app.state.db)
    yield
    if client is not None:
        client.close()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_origin_regex=settings.cors_origin_regex or None,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    register_error_handlers(app)
    app.include_router(auth.router)
    app.include_router(profile.router)
    app.include_router(assessments.router)

    @app.get("/health", tags=["system"])
    async def health():
        return {"status": "ok"}

    return app


app = create_app()
