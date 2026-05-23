#!/usr/bin/env python3
"""reviews_lineage.py — declare (or remove) the reviews data product's lineage.

Phase A part 2. The review-service data product references products by `sku` —
the identifier the inventory domain owns — so we connect them in OpenMetadata
with a single directed edge:

    capstone-postgres.capstone.inventory.stock   (Table, inventory-service)
        │  referenced by
        ▼
    capstone-postgres.capstone.reviews.reviews    (Table, review-service)

This is kept SEPARATE from the permanent lineage.py (which declares the
orders -> order-placed -> notifications spine) because review-service is a
temporary demo product: `up` adds the edge, `down` removes it, leaving the
permanent spine untouched.

Mirrors lineage.py exactly (stdlib only; OM_HOST/OM_JWT from env), so it runs
either in the ingestion image or host-side against a port-forwarded server.

Usage:  OM_HOST=... OM_JWT=... ./reviews_lineage.py up|down

VERIFY-POINTS (OpenMetadata 1.12.8 API shapes — same caveats as lineage.py):
  * Entity-by-FQN: GET /api/v1/tables/name/{fqn} returns the entity with `id`.
  * Add edge: PUT /api/v1/lineage with
      {"edge": {"fromEntity": {"id","type"}, "toEntity": {"id","type"}}}.
  * Delete edge: DELETE /api/v1/lineage/{fromType}/{fromId}/{toType}/{toId}.
    The delete-by-ids path is the shape most likely to need a tweak.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

HOST = os.environ.get("OM_HOST", "http://openmetadata:8585")
TOKEN = os.environ.get("OM_JWT", "")

PRODUCTS_FQN = "capstone-postgres.capstone.inventory.stock"
REVIEWS_FQN = "capstone-postgres.capstone.reviews.reviews"


def _headers() -> dict:
    return {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


def get_id(fqn: str) -> str:
    url = f"{HOST}/api/v1/tables/name/{urllib.parse.quote(fqn, safe='')}"
    req = urllib.request.Request(url, headers=_headers())
    with urllib.request.urlopen(req, timeout=30) as resp:
        entity = json.load(resp)
    entity_id = entity.get("id")
    if not entity_id:
        raise RuntimeError(f"no id for table {fqn}")
    return entity_id


def add_edge(from_id: str, to_id: str) -> None:
    body = json.dumps(
        {
            "edge": {
                "fromEntity": {"id": from_id, "type": "table"},
                "toEntity": {"id": to_id, "type": "table"},
            }
        }
    ).encode()
    req = urllib.request.Request(
        f"{HOST}/api/v1/lineage", data=body, headers=_headers(), method="PUT"
    )
    urllib.request.urlopen(req, timeout=30).read()


def delete_edge(from_id: str, to_id: str) -> None:
    url = f"{HOST}/api/v1/lineage/table/{from_id}/table/{to_id}"
    req = urllib.request.Request(url, headers=_headers(), method="DELETE")
    try:
        urllib.request.urlopen(req, timeout=30).read()
    except urllib.error.HTTPError as exc:
        if exc.code in (404, 400):  # already gone — fine for an idempotent down
            return
        raise


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in ("up", "down"):
        sys.stderr.write("usage: reviews_lineage.py up|down\n")
        return 2
    if not TOKEN:
        sys.stderr.write("OM_JWT not set\n")
        return 1
    try:
        products = get_id(PRODUCTS_FQN)
        reviews = get_id(REVIEWS_FQN)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(
            f"failed to resolve an entity (did ingestion run after deploy?): {exc}\n"
        )
        return 1
    try:
        if mode == "up":
            add_edge(products, reviews)
            print("lineage declared: inventory.stock -> reviews.reviews")
        else:
            delete_edge(products, reviews)
            print("lineage removed: inventory.stock -> reviews.reviews")
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"lineage {mode} failed: {exc}\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
