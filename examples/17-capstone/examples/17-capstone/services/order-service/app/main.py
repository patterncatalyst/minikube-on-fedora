"""order-service — the §17 capstone's first data product.

r21: REST + Postgres. r23: gRPC stock check against inventory before
persisting. r25: publishes an `order.placed` event to Kafka after persisting,
starting the async spine. GraphQL reads are served by the gateway (r24).

Endpoints:
  GET  /health      — liveness (process is up)
  GET  /healthz     — readiness (can reach Postgres)
  POST /orders      — place an order (checks inventory, persists, emits event)
  GET  /orders      — list orders
  GET  /orders/{id} — fetch one order
"""

from __future__ import annotations

import logging
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, status
from sqlalchemy import select

from app.config import settings
from app.db import SessionLocal, check_db, dispose, init_schema
from app.events import publish_order_placed, start_producer, stop_producer
from app.inventory_client import (
    InventoryUnreachable,
    StockUnavailable,
    check_stock,
)
from app.models import Order
from app.schemas import OrderCreate, OrderResponse

logger = logging.getLogger("order-service")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Managed Lifecycle: bring up schema + Kafka producer on startup,
    # tear them down cleanly on shutdown.
    await init_schema()
    await start_producer()
    yield
    await stop_producer()
    await dispose()


app = FastAPI(
    title="order-service",
    version="0.3.0",
    description="Order data product for the §17 capstone data mesh.",
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


@app.post("/orders", response_model=OrderResponse, status_code=status.HTTP_201_CREATED, tags=["orders"])
async def place_order(payload: OrderCreate) -> Order:
    # r23: validate stock with inventory-service over gRPC before persisting.
    try:
        await check_stock(payload.item_sku, payload.quantity)
    except StockUnavailable as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"insufficient stock for {exc.sku} ({exc.quantity_on_hand} on hand)",
        )
    except InventoryUnreachable as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"inventory-service unreachable: {exc}",
        )

    order = Order(
        id=str(uuid.uuid4()),
        customer_id=payload.customer_id,
        item_sku=payload.item_sku,
        quantity=payload.quantity,
        amount=payload.amount,
    )
    async with SessionLocal() as session:
        session.add(order)
        await session.commit()
        await session.refresh(order)

    # r25: emit the event after the order is durably persisted. A publish
    # failure must not fail the order (it's already committed) — we log it.
    # The dual-write gap this leaves is addressed by the outbox pattern in
    # production (see app/events.py and §17).
    try:
        await publish_order_placed(order)
    except Exception as exc:  # noqa: BLE001 — best-effort emit
        logger.warning("failed to publish order.placed for %s: %s", order.id, exc)

    return order


@app.get("/orders", response_model=list[OrderResponse], tags=["orders"])
async def list_orders(limit: int = 100) -> list[Order]:
    async with SessionLocal() as session:
        result = await session.execute(
            select(Order).order_by(Order.created_at.desc()).limit(limit)
        )
        return list(result.scalars().all())


@app.get("/orders/{order_id}", response_model=OrderResponse, tags=["orders"])
async def get_order(order_id: str) -> Order:
    async with SessionLocal() as session:
        order = await session.get(Order, order_id)
    if order is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="order not found"
        )
    return order
