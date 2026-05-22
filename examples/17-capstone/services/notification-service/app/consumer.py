"""Kafka consumer for notification-service.

r25 consumed ad-hoc JSON. r25b consumes registered **Avro**: each message is
in the Confluent Wire Format (magic + schema id + Avro bytes), and the
consumer fetches the writer schema from Apicurio by that id to decode it (see
`avro_serde.py`). The consumer holds no local copy of the schema — it learns
it from the registry, which is the point of a runtime contract.

Managed Lifecycle: the consumer runs as a background asyncio task started and
cancelled by the app lifespan.

At-least-once delivery (Kleppmann, DDIA): Kafka can redeliver, so the consumer
is idempotent — keyed by `order_id`, a redelivery overwrites rather than
duplicates. (r25 keeps received events in memory — a deliberate stand-in; the
real `notifications` table + Alembic arrive in a follow-on.)
"""

from __future__ import annotations

import asyncio
import logging
from collections import OrderedDict

from aiokafka import AIOKafkaConsumer

from app.avro_serde import AvroRegistrySerde
from app.config import settings

logger = logging.getLogger("notification-service.consumer")

_MAX_KEEP = 100
_received: "OrderedDict[str, dict]" = OrderedDict()
_task: asyncio.Task | None = None

# Consumer-only serde: no local schema; decode() fetches writer schemas by id.
_serde = AvroRegistrySerde(
    registry_url=settings.apicurio_url,
    subject=settings.kafka_order_topic,
)


def received_events() -> list[dict]:
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
        "kafka consumer started (topic=%s group=%s, Avro via %s)",
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
            order_id = event.get("order_id", f"offset-{msg.offset}")
            _received[order_id] = event  # idempotent by order_id
            _received.move_to_end(order_id)
            while len(_received) > _MAX_KEEP:
                _received.popitem(last=False)
            logger.info("received %s for order %s", event.get("event_type"), order_id)
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
