"""inventory-service — a §17 capstone data product.

r23 scope: REST health surface + a gRPC server implementing
InventoryService.CheckStock, backed by the `stock` table in the service's
`inventory` schema. The gRPC server runs in the same asyncio loop as
FastAPI, started/stopped by the lifespan — one process, two ports.

Endpoints:
  GET /health        — liveness (process is up)
  GET /healthz       — readiness (can reach Postgres)
  GET /stock         — list current stock (read-only convenience for demos)
gRPC:
  InventoryService/CheckStock  (port from settings.grpc_port, default 50051)
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status
from sqlalchemy import select

from app.config import settings
from app.db import SessionLocal, check_db, dispose, init_schema, seed_demo_stock
from app.grpc_server import start_grpc_server
from app.models import Stock


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: schema + tables + demo stock, then the gRPC server.
    await init_schema()
    await seed_demo_stock()
    grpc_server = await start_grpc_server()
    app.state.grpc_server = grpc_server
    yield
    # Shutdown: stop gRPC first (drain in-flight calls), then the DB pool.
    await grpc_server.stop(grace=5)
    await dispose()


app = FastAPI(
    title="inventory-service",
    version="0.2.0",
    description="inventory-service data product for the §17 capstone — REST health + gRPC CheckStock.",
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


@app.get("/stock", tags=["inventory"])
async def list_stock() -> list[dict]:
    """List current stock levels — a read-only convenience for demos/debugging."""
    async with SessionLocal() as session:
        rows = (await session.execute(select(Stock))).scalars().all()
    return [{"sku": r.sku, "quantity_on_hand": r.quantity_on_hand} for r in rows]
