"""Kafka consumer for notification-service.

Consumes registered **Avro** `order.placed` events (Confluent Wire Format;
the writer schema is fetched from Apicurio by the id in each message — see
`avro_serde.py`) and **persists** each one to the `notifications` table.

r25c change: received events are now written to Postgres (the `notifications`
table created by Alembic), replacing the in-memory list. The benefit is real
durability — a notification survives a pod restart, which the in-memory
version did not.

At-least-once delivery (Kleppmann, DDIA): Kafka can redeliver, so the write is
idempotent — an INSERT ... ON CONFLICT DO NOTHING keyed by the unique
`order_id` makes a redelivery a no-op rather than a duplicate row.

Managed Lifecycle: the consumer runs as a background asyncio task started and
cancelled by the app lifespan.
"""

from __future__ import annotations

import asyncio
import logging

from aiokafka import AIOKafkaConsumer
from sqlalchemy import desc, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.avro_serde import AvroRegistrySerde
from app.config import settings
from app.db import SessionLocal
from app.models import Notification

logger = logging.getLogger("notification-service.consumer")

_task: asyncio.Task | None = None

# Consumer-only serde: no local schema; decode() fetches writer schemas by id.
_serde = AvroRegistrySerde(
    registry_url=settings.apicurio_url,
    subject=settings.kafka_order_topic,
)

# Columns we persist (the event fields we know about).
_FIELDS = ("event_type", "customer_id", "item_sku", "quantity", "amount", "status")


async def persist_event(event: dict) -> None:
    """Idempotently insert one consumed event as a notification row."""
    order_id = event["order_id"]
    values = {
        "id": order_id,  # order_id is a stable, unique key — reuse it as PK
        "order_id": order_id,
        **{f: event.get(f) for f in _FIELDS},
    }
    stmt = (
        pg_insert(Notification)
        .values(**values)
        .on_conflict_do_nothing(index_elements=["order_id"])
    )
    async with SessionLocal() as session:
        await session.execute(stmt)
        await session.commit()


async def recent_notifications(limit: int = 100) -> list[dict]:
    """Read recent notifications from the table (newest first)."""
    async with SessionLocal() as session:
        rows = (
            await session.execute(
                select(Notification).order_by(desc(Notification.created_at)).limit(limit)
            )
        ).scalars().all()
    return [
        {
            "order_id": r.order_id,
            "event_type": r.event_type,
            "customer_id": r.customer_id,
            "item_sku": r.item_sku,
            "quantity": r.quantity,
            "amount": r.amount,
            "status": r.status,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]


async def _consume_loop() -> None:
    consumer = AIOKafkaConsumer(
        settings.kafka_order_topic,
        bootstrap_servers=settings.kafka_bootstrap,
        group_id=settings.kafka_group,
        enable_auto_commit=True,
        auto_offset_reset="earliest",
    )
    await consumer.start()
    logger.info(
        "kafka consumer started (topic=%s group=%s, Avro via %s) — persisting to DB",
        settings.kafka_order_topic,
        settings.kafka_group,
        settings.apicurio_url,
    )
    try:
        async for msg in consumer:
            try:
                event = await _serde.decode(msg.value)
            except Exception as exc:  # noqa: BLE001 — bad/undecodable message
                logger.warning("skipping undecodable message at offset %s: %s", msg.offset, exc)
                continue
            try:
                await persist_event(event)
            except Exception as exc:  # noqa: BLE001 — surface but keep consuming
                logger.error("failed to persist event for order %s: %s", event.get("order_id"), exc)
                continue
            logger.info("persisted %s for order %s", event.get("event_type"), event.get("order_id"))
    finally:
        await consumer.stop()
        logger.info("kafka consumer stopped")


async def start_consumer() -> None:
    global _task
    _task = asyncio.create_task(_consume_loop())


async def stop_consumer() -> None:
    global _task
    if _task is not None:
        _task.cancel()
        try:
            await _task
        except asyncio.CancelledError:
            pass
        _task = None
