#!/usr/bin/env python3
"""lineage.py — declare the cross-product lineage spine in OpenMetadata.

DECISION D (CAP-023): lineage is declared explicitly via the first-class
lineage REST API (PUT /api/v1/lineage), not inferred. OpenMetadata derives
lineage automatically only from query logs / dbt, which the capstone doesn't
have; and a Table→Topic→Table chain crosses entity types, which the API
handles cleanly. This runs as the THIRD ingestion Job, after the Postgres and
Kafka Jobs, because the three entities must already exist to be linked.

The spine (one directed edge per producer/consumer relationship):

    capstone-postgres.capstone.orders.orders            (Table, order-service)
        │  produces
        ▼
    capstone-kafka.order-placed                          (Topic)
        │  consumed by
        ▼
    capstone-postgres.capstone.notifications.notifications  (Table, notification-svc)

Stdlib only (urllib/json), so it runs in the ingestion image unchanged.
Idempotent: PUT /api/v1/lineage upserts an edge, so re-running is a no-op.

VERIFY-POINTS (OpenMetadata 1.12.8 API shapes; confirm at build time):
  * Entity-by-FQN lookups: GET /api/v1/tables/name/{fqn} and
    GET /api/v1/topics/name/{fqn} return the entity with an `id`.
  * AddLineage payload: {"edge": {"fromEntity": {"id","type"}, "toEntity":
    {"id","type"}}} with entity types "table" and "topic". This payload shape
    is stable across 1.x but is the most likely thing to need a tweak.
  * FQN convention: Table = {service}.{database}.{schema}.{table};
    Topic = {service}.{topic}. These follow from the serviceName values set in
    postgres.yaml / kafka.yaml.
"""
import json
import os
import sys
import urllib.parse
import urllib.request

HOST = os.environ.get("OM_HOST", "http://openmetadata:8585")
TOKEN = os.environ.get("OM_JWT", "")

ORDERS_FQN = "capstone-postgres.capstone.orders.orders"
TOPIC_FQN = "capstone-kafka.order-placed"
NOTIFS_FQN = "capstone-postgres.capstone.notifications.notifications"


def _headers() -> dict:
    return {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


def get_id(entity_path: str, fqn: str) -> str:
    """Resolve an entity FQN to its UUID. entity_path is 'tables' or 'topics'."""
    url = f"{HOST}/api/v1/{entity_path}/name/{urllib.parse.quote(fqn, safe='')}"
    req = urllib.request.Request(url, headers=_headers())
    with urllib.request.urlopen(req, timeout=30) as resp:
        entity = json.load(resp)
    entity_id = entity.get("id")
    if not entity_id:
        raise RuntimeError(f"no id for {entity_path} {fqn}")
    return entity_id


def put_edge(from_id: str, from_type: str, to_id: str, to_type: str) -> None:
    body = json.dumps(
        {
            "edge": {
                "fromEntity": {"id": from_id, "type": from_type},
                "toEntity": {"id": to_id, "type": to_type},
            }
        }
    ).encode()
    req = urllib.request.Request(
        f"{HOST}/api/v1/lineage", data=body, headers=_headers(), method="PUT"
    )
    urllib.request.urlopen(req, timeout=30).read()


def main() -> int:
    if not TOKEN:
        sys.stderr.write("OM_JWT not set; the Job must inject a bearer token\n")
        return 1
    try:
        orders = get_id("tables", ORDERS_FQN)
        topic = get_id("topics", TOPIC_FQN)
        notifs = get_id("tables", NOTIFS_FQN)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(
            f"failed to resolve an entity (did the Postgres/Kafka Jobs run?): {exc}\n"
        )
        return 1
    try:
        put_edge(orders, "table", topic, "topic")
        put_edge(topic, "topic", notifs, "table")
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"failed to declare a lineage edge: {exc}\n")
        return 1
    print("lineage declared: orders -> order-placed -> notifications")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
