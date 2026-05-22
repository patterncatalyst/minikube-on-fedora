"""Alembic migration environment for notification-service (async).

Adapted from Alembic's `-t async` template, with three project-specific
adjustments (each one a documented async/Alembic pitfall):

1. **Async bridge.** Alembic's default env.py is sync-only; we build an
   AsyncEngine and run the migration body via `connection.run_sync(...)`.
2. **URL from settings, not the .ini.** We never call
   `config.set_main_option("sqlalchemy.url", ...)` — that routes the URL
   through configparser, which treats `%` as interpolation and would corrupt a
   CloudNativePG password containing one. We build the engine directly from
   `settings.database_url`.
3. **Per-service version table.** This is one Postgres database with a schema
   per service (CAP-003). If every service kept its `alembic_version` in
   `public`, they'd collide. We put it in this service's own schema via
   `version_table_schema`, so each service has an isolated migration history.
   Because the version table lives in the schema, the schema must exist before
   Alembic stamps it — so we `CREATE SCHEMA IF NOT EXISTS` first and commit.

Importing `app.models` is what populates `Base.metadata` (forgetting this is
the classic "empty autogenerate" trap).
"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.config import settings
from app.models import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata
SCHEMA = settings.service_schema


def do_run_migrations(connection) -> None:
    # The per-service schema must exist before the version table is stamped
    # into it. Idempotent and committed before the migration transaction.
    connection.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{SCHEMA}"'))
    connection.commit()

    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        version_table_schema=SCHEMA,
        include_schemas=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    engine = create_async_engine(settings.database_url, pool_pre_ping=True)
    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await engine.dispose()


def run_migrations_offline() -> None:
    """Offline ('--sql') mode: emit SQL against the URL without a DBAPI."""
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        version_table_schema=SCHEMA,
        include_schemas=True,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_async_migrations())
