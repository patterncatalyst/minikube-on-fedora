"""Kafka producer for order-service — publishes `order.placed` as registered Avro.

r25 published this event as ad-hoc JSON. r25b makes it a real **runtime
contract**: the event is serialized as Avro against a schema registered in
Apicurio, and the bytes carry the schema id (Confluent Wire Format, see
`avro_serde.py`). The consumer fetches that schema by id to decode — neither
side can encode or decode without the registry.

order-service *owns* this contract: the canonical schema lives in
`schemas/order-placed.avsc` alongside the service that produces it.

Managed Lifecycle (Kubernetes Patterns): the producer starts and the schema
registers on app startup; the producer stops on shutdown. Publishing happens
after the order is durably persisted (the dual-write caveat from CAP-017 and
§17 still applies — the outbox pattern is the production answer).
"""

from __future__ import annotations

import json
import logging
import os

from aiokafka import AIOKafkaProducer

from app.avro_serde import AvroRegistrySerde
from app.config import settings

logger = logging.getLogger("order-service.events")

# Canonical Avro schema for the event this service owns.
_SCHEMA_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "schemas",
    "order-placed.avsc",
)
with open(_SCHEMA_PATH) as _f:
    _ORDER_PLACED_SCHEMA = json.load(_f)

_producer: AIOKafkaProducer | None = None
_serde: AvroRegistrySerde | None = None


async def start_producer() -> None:
    global _producer, _serde
    _producer = AIOKafkaProducer(bootstrap_servers=settings.kafka_bootstrap)
    await _producer.start()
    # Register the Avro schema with Apicurio and cache its id for encoding.
    _serde = AvroRegistrySerde(
        registry_url=settings.apicurio_url,
        subject=settings.kafka_order_subject,
        schema_dict=_ORDER_PLACED_SCHEMA,
    )
    schema_id = await _serde.register()
    logger.info(
        "kafka producer started; order.placed Avro schema registered id=%s (subject=%s)",
        schema_id,
        settings.kafka_order_subject,
    )


async def stop_producer() -> None:
    global _producer
    if _producer is not None:
        await _producer.stop()
        _producer = None


async def publish_order_placed(order) -> None:
    """Publish an order.placed event as registered Avro, keyed by order id."""
    if _producer is None or _serde is None:
        logger.warning("producer not started; skipping order.placed for %s", order.id)
        return

    created = getattr(order, "created_at", None)
    event = {
        "event_type": "order.placed",
        "order_id": order.id,
        "customer_id": order.customer_id,
        "item_sku": order.item_sku,
        "quantity": order.quantity,
        "amount": str(order.amount),
        "status": str(order.status),
        "created_at": created.isoformat() if hasattr(created, "isoformat") else str(created),
    }
    await _producer.send_and_wait(
        settings.kafka_order_topic,
        key=order.id.encode(),
        value=_serde.encode(event),
    )
    logger.info("published order.placed (Avro) for %s", order.id)
