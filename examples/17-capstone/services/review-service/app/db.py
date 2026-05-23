"""Database wiring for review-service.

Async SQLAlchemy 2.0 engine + session factory, plus a startup helper that
ensures the service's schema exists before creating any tables.

CAP-004: create-if-not-exists via metadata.create_all. Schema *evolution*
(Alembic) is deferred to a later iteration.
"""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import settings
from app.models import Base

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)

SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def init_schema() -> None:
    """Create the service's schema (and any tables) if they don't exist."""
    async with engine.begin() as conn:
        await conn.execute(
            text(f'CREATE SCHEMA IF NOT EXISTS "{settings.service_schema}"')
        )
        await conn.run_sync(Base.metadata.create_all)


async def check_db() -> bool:
    """Lightweight connectivity check for the readiness probe."""
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def seed_if_empty() -> None:
    """Seed a few demo reviews if the table is empty.

    The SKUs intentionally match product identifiers the inventory/product
    domain owns (e.g. SKU-ABC-42), so the catalog and lineage demo has data
    that visibly relates reviews to products. Idempotent: only seeds when the
    table has no rows, so re-deploys don't duplicate.
    """
    import uuid

    from sqlalchemy import func, select

    from app.models import Review

    async with SessionLocal() as session:
        count = await session.scalar(select(func.count()).select_from(Review))
        if count:
            return
        demo = [
            ("SKU-ABC-42", 5, "cust-1001", "Solid, would buy again."),
            ("SKU-ABC-42", 4, "cust-1002", "Good value."),
            ("SKU-XYZ-7", 3, "cust-1003", "Does the job."),
            ("SKU-XYZ-7", 5, "cust-1004", "Exceeded expectations."),
        ]
        for sku, rating, reviewer, comment in demo:
            session.add(
                Review(
                    id=str(uuid.uuid4()),
                    sku=sku,
                    rating=rating,
                    reviewer=reviewer,
                    comment=comment,
                )
            )
        await session.commit()


async def dispose() -> None:
    await engine.dispose()
