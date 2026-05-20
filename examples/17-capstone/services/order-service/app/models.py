"""SQLAlchemy models for order-service.

The Order table lives in the service's own schema (`orders`), enforcing
the per-service data ownership boundary (CAP-003). order-service is the
only service that writes this schema.
"""

from __future__ import annotations

import datetime as dt
import enum

from sqlalchemy import String, Numeric, DateTime, Enum as SAEnum
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.config import settings


class Base(DeclarativeBase):
    pass


class OrderStatus(str, enum.Enum):
    placed = "placed"
    paid = "paid"
    shipped = "shipped"
    cancelled = "cancelled"


class Order(Base):
    __tablename__ = "orders"
    # Bind the table to the service's schema. The schema itself is created
    # at startup (see db.init_schema) before metadata.create_all runs.
    __table_args__ = {"schema": settings.service_schema}

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    customer_id: Mapped[str] = mapped_column(String(64), index=True)
    item_sku: Mapped[str] = mapped_column(String(64))
    quantity: Mapped[int] = mapped_column()
    amount: Mapped[float] = mapped_column(Numeric(12, 2))
    status: Mapped[OrderStatus] = mapped_column(
        SAEnum(OrderStatus, name="order_status", schema=settings.service_schema),
        default=OrderStatus.placed,
    )
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: dt.datetime.now(dt.timezone.utc)
    )
