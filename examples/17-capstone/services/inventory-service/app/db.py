"""Database wiring for inventory-service.

Async SQLAlchemy 2.0 engine + session factory, plus startup helpers that
ensure the service's schema exists, create its tables, and seed a little
demo stock so the gRPC CheckStock call has something to answer.

CAP-004: create-if-not-exists via metadata.create_all. Schema *evolution*
(Alembic) is deferred to a later iteration.
"""

from __future__ import annotations

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import settings
from app.models import Base, Stock

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)

SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

# Demo stock seeded on startup if the table is empty. Gives the smoke test a
# known in-stock SKU and a known out-of-stock SKU.
DEMO_STOCK = {
    "WIDGET-001": 50,   # in stock
    "WIDGET-OOS": 0,    # out of stock
}


async def init_schema() -> None:
    """Create the service's schema and tables if they don't exist."""
    async with engine.begin() as conn:
        await conn.execute(
            text(f'CREATE SCHEMA IF NOT EXISTS "{settings.service_schema}"')
        )
        await conn.run_sync(Base.metadata.create_all)


async def seed_demo_stock() -> None:
    """Insert demo stock rows if the table is empty (idempotent)."""
    async with SessionLocal() as session:
        existing = await session.execute(select(Stock.sku).limit(1))
        if existing.first() is not None:
            return
        for sku, qty in DEMO_STOCK.items():
            session.add(Stock(sku=sku, quantity_on_hand=qty))
        await session.commit()


async def check_db() -> bool:
    """Lightweight connectivity check for the readiness probe."""
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def dispose() -> None:
    await engine.dispose()
