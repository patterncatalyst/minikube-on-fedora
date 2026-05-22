"""Database wiring for notification-service.

Async SQLAlchemy 2.0 engine + session factory.

r25c: the service's schema and tables are created and evolved by **Alembic
migrations** (run by an init container before the app starts — see CAP-021),
NOT by `Base.metadata.create_all`. The previous `init_schema()` helper is gone:
when the app process starts, the `notifications` schema and table already
exist, so the app never issues DDL. This is the create-all retirement called
for in CAP-004, applied to this service.
"""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import settings

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)

SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


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
