"""SQLAlchemy models for review-service.

The Review table lives in the service's own schema (`reviews`), enforcing
the per-service data ownership boundary (CAP-003). review-service is the only
service that writes this schema. Reviews reference a product `sku` — the same
identifier the inventory/product domain owns — which is the basis for the
cross-product lineage edge we declare in OpenMetadata (reviews -> products).
"""

from __future__ import annotations

import datetime as dt

from sqlalchemy import String, Integer, Text, DateTime
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.config import settings


class Base(DeclarativeBase):
    pass


class Review(Base):
    __tablename__ = "reviews"
    # Bind the table to the service's schema. The schema itself is created at
    # startup (see db.init_schema) before metadata.create_all runs.
    __table_args__ = {"schema": settings.service_schema}

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sku: Mapped[str] = mapped_column(String(64), index=True)
    rating: Mapped[int] = mapped_column(Integer)            # 1..5 (validated at the API)
    reviewer: Mapped[str] = mapped_column(String(64), index=True)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: dt.datetime.now(dt.timezone.utc)
    )
