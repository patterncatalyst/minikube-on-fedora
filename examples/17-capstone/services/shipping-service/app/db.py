"""Database wiring for shipping-service.

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


async def dispose() -> None:
    await engine.dispose()
