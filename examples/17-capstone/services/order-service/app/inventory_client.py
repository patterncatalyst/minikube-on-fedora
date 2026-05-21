"""gRPC client for order-service → inventory-service.

Wraps the InventoryService.CheckStock call. The generated stubs live in the
service's committed `gen/` tree (option b); we add it to sys.path so
`capstone.inventory.v1` is importable in the container and locally.

This is the order flow's one synchronous cross-service dependency: before an
order is persisted, order-service asks inventory-service whether the SKU is
available. gRPC fits here because it's a tight request/response between two
internal services (CAP-012 — "which constraint matters for this interaction").
"""

from __future__ import annotations

import os
import sys

_GEN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "gen")
if _GEN not in sys.path:
    sys.path.insert(0, _GEN)

import grpc  # noqa: E402
from capstone.inventory.v1 import (  # noqa: E402
    inventory_pb2,
    inventory_pb2_grpc,
)

from app.config import settings  # noqa: E402


class StockUnavailable(Exception):
    """Raised when the requested SKU/quantity is not available."""

    def __init__(self, sku: str, quantity_on_hand: int):
        self.sku = sku
        self.quantity_on_hand = quantity_on_hand
        super().__init__(f"insufficient stock for {sku}: {quantity_on_hand} on hand")


class InventoryUnreachable(Exception):
    """Raised when the inventory gRPC call fails (service down, timeout, etc.)."""


async def check_stock(sku: str, quantity: int, *, timeout: float = 3.0) -> int:
    """Return quantity_on_hand if available; raise otherwise.

    Raises StockUnavailable if the SKU lacks the requested quantity, or
    InventoryUnreachable if the gRPC call itself fails (fail closed — we do
    not place an order we couldn't validate).
    """
    try:
        async with grpc.aio.insecure_channel(settings.inventory_grpc_addr) as channel:
            stub = inventory_pb2_grpc.InventoryServiceStub(channel)
            resp = await stub.CheckStock(
                inventory_pb2.CheckStockRequest(sku=sku, quantity=quantity),
                timeout=timeout,
            )
    except grpc.aio.AioRpcError as exc:  # network/timeout/unavailable
        raise InventoryUnreachable(str(exc)) from exc

    if not resp.available:
        raise StockUnavailable(sku, resp.quantity_on_hand)
    return resp.quantity_on_hand
