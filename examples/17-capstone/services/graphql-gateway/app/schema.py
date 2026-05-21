"""GraphQL schema for the gateway (Strawberry).

Defines the unified graph the client queries. The `order` query resolves an
order from order-service (REST); the nested `stock` field on that order
resolves from inventory-service (gRPC). The client asks one question and
gets a stitched answer spanning two services and two protocols — the value
GraphQL adds over calling each service directly (CAP-012).

Strawberry auto-converts snake_case Python fields to camelCase in the schema
(item_sku → itemSku, quantity_on_hand → quantityOnHand).
"""

from __future__ import annotations

import strawberry

from app.clients import fetch_order, fetch_stock


@strawberry.type
class Stock:
    sku: str
    quantity_on_hand: int
    # available is relative to the order's quantity (computed when resolved
    # in the context of an order).
    available: bool


@strawberry.type
class Order:
    id: strawberry.ID
    customer_id: str
    item_sku: str
    quantity: int
    amount: str
    status: str
    created_at: str

    @strawberry.field
    async def stock(self) -> Stock | None:
        """Resolve the live stock for this order's SKU from inventory (gRPC)."""
        on_hand, available = await fetch_stock(self.item_sku, self.quantity)
        return Stock(
            sku=self.item_sku,
            quantity_on_hand=on_hand,
            available=available,
        )


def _order_from_rest(data: dict) -> Order:
    """Map order-service's REST JSON onto the GraphQL Order type."""
    return Order(
        id=data["id"],
        customer_id=data["customer_id"],
        item_sku=data["item_sku"],
        quantity=data["quantity"],
        amount=str(data["amount"]),
        status=str(data["status"]),
        created_at=str(data["created_at"]),
    )


@strawberry.type
class Query:
    @strawberry.field
    async def order(self, id: strawberry.ID) -> Order | None:
        """Fetch a single order (REST) — its `stock` field federates to gRPC."""
        data = await fetch_order(str(id))
        return _order_from_rest(data) if data is not None else None


schema = strawberry.Schema(query=Query)
