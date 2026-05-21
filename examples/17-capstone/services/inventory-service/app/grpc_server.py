"""gRPC server for inventory-service — implements InventoryService.CheckStock.

The generated stubs live in the service's `gen/` tree (committed by
scripts/gen-protos.sh, option b). We add that tree to sys.path so the
package `capstone.inventory.v1` is importable both in the container
(/opt/app-root/src/gen) and locally (services/inventory-service/gen).

The server runs in the same asyncio event loop as the FastAPI app, started
and stopped by the app's lifespan (see app/main.py) — one process, one
container, two ports (HTTP for REST/health, gRPC for CheckStock).
"""

from __future__ import annotations

import os
import sys

# Make the committed stubs importable: <service-root>/gen on sys.path.
_GEN = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "gen")
if _GEN not in sys.path:
    sys.path.insert(0, _GEN)

import grpc  # noqa: E402
from capstone.inventory.v1 import (  # noqa: E402
    inventory_pb2,
    inventory_pb2_grpc,
)

from app.config import settings  # noqa: E402
from app.db import SessionLocal  # noqa: E402
from app.models import Stock  # noqa: E402


class InventoryServicer(inventory_pb2_grpc.InventoryServiceServicer):
    async def CheckStock(self, request, context):
        """Report whether `sku` has at least `quantity` on hand."""
        async with SessionLocal() as session:
            row = await session.get(Stock, request.sku)
        on_hand = row.quantity_on_hand if row is not None else 0
        available = request.quantity > 0 and on_hand >= request.quantity
        return inventory_pb2.CheckStockResponse(
            available=available,
            quantity_on_hand=on_hand,
        )


async def start_grpc_server() -> "grpc.aio.Server":
    """Start the async gRPC server and return it (caller stops it on shutdown)."""
    server = grpc.aio.server()
    inventory_pb2_grpc.add_InventoryServiceServicer_to_server(
        InventoryServicer(), server
    )
    server.add_insecure_port(f"0.0.0.0:{settings.grpc_port}")
    await server.start()
    return server
