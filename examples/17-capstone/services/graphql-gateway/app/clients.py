"""Downstream clients for the GraphQL gateway.

The gateway federates by *calling* the services it composes:
  - order-service over REST (httpx)
  - inventory-service over gRPC (the committed capstone.inventory.v1 stubs)

The gRPC stubs live in the gateway's committed `gen/` tree (option b,
CAP-013); we add it to sys.path so `capstone.inventory.v1` imports in the
container and locally.

This is exactly where the protocol comparison (CAP-012) becomes concrete:
one resolver path uses REST, another uses gRPC, and GraphQL stitches both
into a single response shaped by the client's query.
"""

from __future__ import annotations

import os
import sys

_GEN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "gen")
if _GEN not in sys.path:
    sys.path.insert(0, _GEN)

import grpc  # noqa: E402
import httpx  # noqa: E402
from capstone.inventory.v1 import (  # noqa: E402
    inventory_pb2,
    inventory_pb2_grpc,
)

from app.config import settings  # noqa: E402


async def fetch_order(order_id: str) -> dict | None:
    """GET the order from order-service's REST API. None if not found."""
    async with httpx.AsyncClient(base_url=settings.order_rest_url, timeout=5.0) as client:
        resp = await client.get(f"/orders/{order_id}")
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        return resp.json()


async def fetch_stock(sku: str, quantity: int = 1) -> tuple[int, bool]:
    """Ask inventory-service over gRPC for on-hand quantity and availability."""
    async with grpc.aio.insecure_channel(settings.inventory_grpc_addr) as channel:
        stub = inventory_pb2_grpc.InventoryServiceStub(channel)
        resp = await stub.CheckStock(
            inventory_pb2.CheckStockRequest(sku=sku, quantity=quantity),
            timeout=3.0,
        )
    return resp.quantity_on_hand, resp.available
