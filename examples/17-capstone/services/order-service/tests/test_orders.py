"""Service-local tests for order-service.

These run against an in-process app with a SQLite-backed database (no
Postgres required), exercising the REST contract. The deploy-level smoke
test (demos/smoke-order.sh) exercises the real Postgres path in-cluster.

Run locally with: poetry run pytest
"""

from __future__ import annotations

import os

import pytest
from httpx import ASGITransport, AsyncClient

# Point the app at an in-memory SQLite DB before importing it. SQLite doesn't
# support schemas the way Postgres does, so we blank the service_schema for
# the unit test (the real schema separation is exercised in-cluster).
os.environ["SERVICE_SCHEMA"] = ""
os.environ["PG_HOST"] = "sqlite"  # overridden below; presence avoids defaults


@pytest.fixture()
async def client(monkeypatch):
    # Rebuild the database URL to use aiosqlite in-memory for the test.
    from app import config

    monkeypatch.setattr(
        config.settings, "service_schema", "", raising=False
    )

    # Late import so settings overrides take effect.
    import importlib

    from app import db as db_module

    # Swap the engine for an in-memory SQLite async engine.
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

    test_engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    db_module.engine = test_engine
    db_module.SessionLocal = async_sessionmaker(test_engine, expire_on_commit=False)

    from app.models import Base

    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

    await test_engine.dispose()


async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


async def test_place_and_fetch_order(client):
    create = await client.post(
        "/orders",
        json={
            "customer_id": "cust-1001",
            "item_sku": "SKU-ABC-42",
            "quantity": 3,
            "amount": "59.97",
        },
    )
    assert create.status_code == 201
    body = create.json()
    assert body["customer_id"] == "cust-1001"
    assert body["status"] == "placed"
    order_id = body["id"]

    fetch = await client.get(f"/orders/{order_id}")
    assert fetch.status_code == 200
    assert fetch.json()["id"] == order_id

    listing = await client.get("/orders")
    assert listing.status_code == 200
    assert len(listing.json()) == 1


async def test_get_missing_order(client):
    resp = await client.get("/orders/does-not-exist")
    assert resp.status_code == 404
