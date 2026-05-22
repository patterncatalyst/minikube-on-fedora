"""notification-service — a §17 capstone data product (Kafka consumer).

Consumes `order.placed` events from Kafka (its designed role — a consumer-only
data product) and persists them to its `notifications` table.

r25c: the table is created by an Alembic migration run in an init container
before this process starts, so the app issues no DDL — it just consumes and
persists. `/received` reads from the table.

Endpoints:
  GET /health    — liveness (process is up)
  GET /healthz   — readiness (can reach Postgres)
  GET /received  — notifications persisted so far (from the DB, newest first)
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status

from app.config import settings
from app.consumer import recent_notifications, start_consumer, stop_consumer
from app.db import check_db, dispose


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Managed Lifecycle: no schema creation here — migrations ran in the init
    # container (CAP-021). Just start/stop the background Kafka consumer.
    await start_consumer()
    yield
    await stop_consumer()
    await dispose()


app = FastAPI(
    title="notification-service",
    version="0.3.0",
    description="notification-service data product for the §17 capstone — consumes and persists order events.",
    lifespan=lifespan,
)


@app.get("/health", tags=["ops"])
async def health() -> dict[str, str]:
    return {"status": "ok", "service": settings.service_name}


@app.get("/healthz", tags=["ops"])
async def healthz() -> dict[str, str]:
    if not await check_db():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unreachable",
        )
    return {"status": "ready", "service": settings.service_name}


@app.get("/received", tags=["notifications"])
async def received() -> list[dict]:
    """Notifications persisted from consumed events (from the DB, newest first)."""
    return await recent_notifications()
