"""Database wiring for shipping-report.

Plain synchronous psycopg3: a batch job is a short-lived process, not a
long-running service, so there's no connection pool to manage: connect,
do the work, disconnect.
"""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import psycopg

from app.config import settings

ZONES = ("warehouse-a", "warehouse-b", "warehouse-c")


@contextmanager
def connection() -> Iterator[psycopg.Connection]:
    conn = psycopg.connect(settings.dsn)
    try:
        yield conn
    finally:
        conn.close()


def ensure_schema(conn: psycopg.Connection) -> None:
    """Create the shipping schema and the demo shipment_events table."""
    with conn.cursor() as cur:
        cur.execute(f'CREATE SCHEMA IF NOT EXISTS "{settings.service_schema}"')
        cur.execute(
            f"""
            CREATE TABLE IF NOT EXISTS "{settings.service_schema}".shipment_events (
                id SERIAL PRIMARY KEY,
                destination_zone TEXT NOT NULL,
                weight_kg NUMERIC(6, 2) NOT NULL,
                shipped_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )
    conn.commit()


def row_count(conn: psycopg.Connection) -> int:
    with conn.cursor() as cur:
        cur.execute(f'SELECT count(*) FROM "{settings.service_schema}".shipment_events')
        (count,) = cur.fetchone()
        return int(count)


def seed(conn: psycopg.Connection, count: int) -> int:
    """Insert `count` deterministic demo rows. Idempotent: a no-op if the
    table already has rows, so re-running `seed` (e.g. from a retried Pod)
    never duplicates data."""
    if row_count(conn) > 0:
        return 0
    with conn.cursor() as cur:
        rows = [
            (ZONES[i % len(ZONES)], 1.5 + (i % 40) * 0.25)
            for i in range(count)
        ]
        cur.executemany(
            f"""INSERT INTO "{settings.service_schema}".shipment_events
                (destination_zone, weight_kg) VALUES (%s, %s)""",
            rows,
        )
    conn.commit()
    return count


def partition(
    conn: psycopg.Connection, partition_index: int, partition_count: int
) -> Iterator[tuple[int, str, float, str]]:
    """Yield the rows this partition owns: id modulo partition_count. This
    is the Indexed Job's own partitioning scheme; JOB_COMPLETION_INDEX
    selects the slice, and no two indexes ever see the same row."""
    with conn.cursor() as cur:
        cur.execute(
            f"""SELECT id, destination_zone, weight_kg, shipped_at
                FROM "{settings.service_schema}".shipment_events
                WHERE id %% %s = %s
                ORDER BY id""",
            (partition_count, partition_index),
        )
        for row_id, zone, weight, shipped_at in cur.fetchall():
            yield row_id, zone, float(weight), shipped_at.isoformat()
