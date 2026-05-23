"""Database wiring for order-service.

Async SQLAlchemy 2.0 engine + session factory, plus a startup helper that
ensures the service's schema exists before creating its tables.

CAP-004: r21 uses metadata.create_all (create-if-not-exists). Schema
*evolution* (Alembic) is deferred to a later iteration.
"""

from __future__ import annotations

import asyncio
import logging

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import settings
from app.models import Base

logger = logging.getLogger("order-service.db")

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)

SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def init_schema(max_attempts: int = 30, max_delay: float = 4.0) -> None:
    """Create the service's schema and tables if they don't exist.

    Retries the first connection with capped backoff. On a cold cluster the
    database may not be reachable the instant this service starts, and because
    order-service is meshed, its istio-proxy must finish programming routes
    before any outbound connection (DNS included) can succeed. Rather than exit
    on the first failure and crash-loop, wait for the dependency to come up. In
    the common case the dependency is ready within a couple of attempts; the
    high ceiling only matters for a genuinely slow cold start, and the whole
    budget is sized to stay inside the startup probe window (values.yaml
    probes.startup).

    Order matters: the schema must exist before metadata.create_all can create
    tables bound to it.
    """
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            async with engine.begin() as conn:
                await conn.execute(
                    text(f'CREATE SCHEMA IF NOT EXISTS "{settings.service_schema}"')
                )
                await conn.run_sync(Base.metadata.create_all)
            if attempt > 1:
                logger.info("database reachable after %d attempt(s)", attempt)
            return
        except Exception as exc:  # noqa: BLE001 — startup tolerates any connect error
            last_exc = exc
            delay = min(float(attempt), max_delay)
            logger.warning(
                "init_schema attempt %d/%d failed (%s); retrying in %.0fs",
                attempt, max_attempts, exc.__class__.__name__, delay,
            )
            await asyncio.sleep(delay)
    raise RuntimeError(
        f"init_schema failed after {max_attempts} attempts"
    ) from last_exc


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
