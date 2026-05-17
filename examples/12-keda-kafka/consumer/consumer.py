#!/usr/bin/env python3
"""
order-processor — a tiny Kafka consumer that simulates work by sleeping
for WORK_SLEEP_S seconds per message. Designed to be scaled by KEDA
based on consumer lag.

Environment variables (all optional, defaults work in-cluster against
the Strimzi cluster from examples/12-keda-kafka/manifests/):

    KAFKA_BROKER   — bootstrap-servers string. Default:
                     my-kafka-kafka-bootstrap.kafka:9092
    KAFKA_TOPIC    — topic to consume. Default: orders
    KAFKA_GROUP    — consumer group. Default: order-processor-group
    WORK_SLEEP_S   — fake processing time per message. Default: 0.5

The graceful SIGTERM handler is the important part. When KEDA scales
this Deployment down (typically when topic lag drops to zero and stays
there for cooldownPeriod seconds), the kubelet sends SIGTERM. Default
Python ignores it until terminationGracePeriodSeconds expires; a
handler exits immediately, making scale-down responsive.
"""
import os
import signal
import sys
import time

from kafka import KafkaConsumer


def graceful_exit(signum, _frame):
    print(f"[order-processor] received signal {signum}; shutting down", flush=True)
    sys.exit(0)


def main() -> None:
    broker = os.environ.get("KAFKA_BROKER", "my-kafka-kafka-bootstrap.kafka:9092")
    topic = os.environ.get("KAFKA_TOPIC", "orders")
    group = os.environ.get("KAFKA_GROUP", "order-processor-group")
    work_sleep_s = float(os.environ.get("WORK_SLEEP_S", "0.5"))

    print(
        f"[order-processor] starting; broker={broker} topic={topic} "
        f"group={group} work_sleep_s={work_sleep_s}",
        flush=True,
    )

    signal.signal(signal.SIGTERM, graceful_exit)
    signal.signal(signal.SIGINT, graceful_exit)

    consumer = KafkaConsumer(
        topic,
        bootstrap_servers=[broker],
        group_id=group,
        auto_offset_reset="earliest",
        enable_auto_commit=True,
        # Short session timeout so a SIGTERM'd replica leaves the group
        # quickly, freeing its partition for another replica.
        session_timeout_ms=10000,
        heartbeat_interval_ms=3000,
    )

    print(f"[order-processor] subscribed to {topic}", flush=True)

    processed = 0
    for msg in consumer:
        processed += 1
        print(
            f"[order-processor] #{processed} offset={msg.offset} "
            f"partition={msg.partition}",
            flush=True,
        )
        time.sleep(work_sleep_s)


if __name__ == "__main__":
    main()
