"""payment-service — a §17 capstone data product (r22 skeleton).

r22 scope: the service stands up, connects to its Postgres schema
(`payments`), and serves health probes. Its domain surface (REST/gRPC/
GraphQL/Kafka, as appropriate to this service) is added in later iterations.

Endpoints:
  GET /health   — liveness (process is up)
  GET /healthz  — readiness (can reach Postgres)
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status

from app.config import settings
from app.db import check_db, dispose, init_schema


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: ensure the service's schema (and any tables) exist.
    await init_schema()
    yield
    # Shutdown: dispose the connection pool cleanly (Managed Lifecycle
    # pattern — Kubernetes Patterns, Ibryam & Huss).
    await dispose()


app = FastAPI(
    title="payment-service",
    version="0.1.0",
    description="payment-service data product for the §17 capstone data mesh (skeleton).",
    lifespan=lifespan,
)


@app.get("/health", tags=["ops"])
async def health() -> dict[str, str]:
    """Liveness: the process is running. Always 200 if we can respond."""
    return {"status": "ok", "service": settings.service_name}


@app.get("/healthz", tags=["ops"])
async def healthz() -> dict[str, str]:
    """Readiness: we can serve traffic (Postgres reachable)."""
    if not await check_db():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unreachable",
        )
    return {"status": "ready", "service": settings.service_name}
