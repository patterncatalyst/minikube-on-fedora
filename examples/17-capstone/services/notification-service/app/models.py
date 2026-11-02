"""SQLAlchemy models for notification-service.

notification-service's first domain table, `notifications`, persists the
order.placed events it consumes. The table lives in the service's own
`notifications` Postgres schema, the per-service ownership boundary.

The table is created and evolved by **Alembic migrations** (see `alembic/`),
not by `Base.metadata.create_all`. This model is the source of truth that the
migration's `target_metadata` is checked against.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.config import settings


class Base(DeclarativeBase):
    pass


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        # Idempotency: at-least-once Kafka delivery means the same order can
        # arrive more than once; one notification per order_id.
        UniqueConstraint("order_id", name="uq_notifications_order_id"),
        {"schema": settings.service_schema},
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    order_id: Mapped[str] = mapped_column(String, nullable=False)
    event_type: Mapped[str] = mapped_column(String, nullable=False)
    customer_id: Mapped[str | None] = mapped_column(String, nullable=True)
    item_sku: Mapped[str | None] = mapped_column(String, nullable=True)
    quantity: Mapped[int | None] = mapped_column(Integer, nullable=True)
    amount: Mapped[str | None] = mapped_column(String, nullable=True)
    status: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
