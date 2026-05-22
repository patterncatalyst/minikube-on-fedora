"""notification-service — a §17 capstone data product (Kafka consumer).

r22 shipped this as a health-only skeleton. r25 gives it its purpose: it
consumes `order.placed` events from Kafka (its designed role — a
consumer-only data product) and exposes what it has received.

Endpoints:
  GET /health    — liveness (process is up)
  GET /healthz   — readiness (can reach Postgres)
  GET /received  — events consumed so far (in-memory; see consumer.py)
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status

from app.config import settings
from app.consumer import received_events, start_consumer, stop_consumer
from app.db import check_db, dispose, init_schema


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Managed Lifecycle: schema, then the background Kafka consumer.
    await init_schema()
    await start_consumer()
    yield
    await stop_consumer()
    await dispose()


app = FastAPI(
    title="notification-service",
    version="0.2.0",
    description="notification-service data product for the §17 capstone — consumes order events.",
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
    """Events consumed from Kafka so far (in-memory; newest last)."""
    return received_events()
