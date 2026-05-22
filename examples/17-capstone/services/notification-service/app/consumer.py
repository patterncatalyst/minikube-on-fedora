"""Kafka consumer for notification-service.

Consumes `order.placed` events and records them. Managed Lifecycle
(Kubernetes Patterns): the consumer runs as a background asyncio task that the
app lifespan starts and cancels.

At-least-once delivery (Kleppmann, *Designing Data-Intensive Applications*):
Kafka can redeliver a message (e.g. after a rebalance or a crash before
commit), so consumers must be **idempotent**. We key the store by `order_id`,
so a redelivered event overwrites rather than duplicates.

r25 keeps received events **in memory** — a deliberate stand-in so the async
flow is observable via `GET /received` without yet introducing a table. The
real `notifications` table (and Alembic migrations, finally retiring
`create_all` for this service per CAP-004) arrive in a follow-on iteration.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections import OrderedDict

from aiokafka import AIOKafkaConsumer

from app.config import settings

logger = logging.getLogger("notification-service.consumer")

_MAX_KEEP = 100
_received: "OrderedDict[str, dict]" = OrderedDict()
_task: asyncio.Task | None = None


def received_events() -> list[dict]:
    """Most-recent-last list of consumed events (for GET /received)."""
    return list(_received.values())


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
        "kafka consumer started (topic=%s group=%s)",
        settings.kafka_order_topic,
        settings.kafka_group,
    )
    try:
        async for msg in consumer:
            try:
                event = json.loads(msg.value)
            except (ValueError, TypeError):
                logger.warning("skipping non-JSON message at offset %s", msg.offset)
                continue
            order_id = event.get("order_id", f"offset-{msg.offset}")
            # Idempotent by order_id: redelivery overwrites, never duplicates.
            _received[order_id] = event
            _received.move_to_end(order_id)
            while len(_received) > _MAX_KEEP:
                _received.popitem(last=False)
            logger.info(
                "received %s for order %s", event.get("event_type"), order_id
            )
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
