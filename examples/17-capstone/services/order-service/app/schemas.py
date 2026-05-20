"""Pydantic schemas for order-service request/response bodies.

Kept separate from the SQLAlchemy models (app.models) so the API contract
(what clients see) is decoupled from the storage model (what Postgres
stores). This separation is also what we'll publish to Apicurio as the
OpenAPI contract in a later iteration.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from pydantic import BaseModel, Field

from app.models import OrderStatus


class OrderCreate(BaseModel):
    customer_id: str = Field(..., max_length=64, examples=["cust-1001"])
    item_sku: str = Field(..., max_length=64, examples=["SKU-ABC-42"])
    quantity: int = Field(..., gt=0, examples=[3])
    amount: Decimal = Field(..., gt=0, examples=[Decimal("59.97")])


class OrderResponse(BaseModel):
    id: str
    customer_id: str
    item_sku: str
    quantity: int
    amount: Decimal
    status: OrderStatus
    created_at: dt.datetime

    model_config = {"from_attributes": True}
