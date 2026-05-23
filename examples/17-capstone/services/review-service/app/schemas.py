"""Pydantic schemas for review-service request/response bodies.

Kept separate from the SQLAlchemy models (app.models) so the API contract
(what clients see) is decoupled from the storage model (what Postgres stores).
This is exactly what review-service publishes to Apicurio as its OpenAPI
discovery contract.
"""

from __future__ import annotations

import datetime as dt

from pydantic import BaseModel, Field


class ReviewCreate(BaseModel):
    sku: str = Field(..., max_length=64, examples=["SKU-ABC-42"])
    rating: int = Field(..., ge=1, le=5, examples=[5])
    reviewer: str = Field(..., max_length=64, examples=["cust-1001"])
    comment: str | None = Field(None, max_length=2000, examples=["Solid, would buy again."])


class ReviewResponse(BaseModel):
    id: str
    sku: str
    rating: int
    reviewer: str
    comment: str | None
    created_at: dt.datetime

    model_config = {"from_attributes": True}
