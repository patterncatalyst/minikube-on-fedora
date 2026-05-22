"""Kafka producer for order-service — publishes `order.placed` events.

Managed Lifecycle (Kubernetes Patterns, Ibryam & Huss): the producer is
started and stopped by the app lifespan, not per-request. Publishing happens
*after* the order is persisted.

On the dual-write problem (Kleppmann, *Designing Data-Intensive
Applications*): writing to Postgres and publishing to Kafka are two separate
systems, so a crash between the commit and the publish can drop the event.
The production-grade fix is the **transactional outbox** — write the event to
an outbox table inside the same DB transaction, then relay it to Kafka
asynchronously. For this tutorial slice we publish after commit and log
failures; the outbox is documented in §17 as the production pattern
(deferred).
"""

from __future__ import annotations

import json
import logging

from aiokafka import AIOKafkaProducer

from app.config import settings

logger = logging.getLogger("order-service.events")

_producer: AIOKafkaProducer | None = None


async def start_producer() -> None:
    global _producer
    _producer = AIOKafkaProducer(bootstrap_servers=settings.kafka_bootstrap)
    await _producer.start()
    logger.info("kafka producer started (bootstrap=%s)", settings.kafka_bootstrap)


async def stop_producer() -> None:
    global _producer
    if _producer is not None:
        await _producer.stop()
        _producer = None


async def publish_order_placed(order) -> None:
    """Publish an order.placed event. Keyed by order id so all events for one
    order land on the same partition (per-key ordering)."""
    if _producer is None:
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
        value=json.dumps(event).encode(),
    )
    logger.info("published order.placed for %s", order.id)
