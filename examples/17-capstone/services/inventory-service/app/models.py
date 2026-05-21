"""SQLAlchemy models for inventory-service.

r23: the inventory domain gets its first real table — `stock` — so the
gRPC CheckStock call has something to check against. The table lives in the
service's own schema (`inventory`), enforcing per-service ownership (CAP-003).
inventory-service is the only service that writes this schema.
"""

from __future__ import annotations

from sqlalchemy import String, Integer
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.config import settings


class Base(DeclarativeBase):
    pass


class Stock(Base):
    __tablename__ = "stock"
    __table_args__ = {"schema": settings.service_schema}

    sku: Mapped[str] = mapped_column(String(64), primary_key=True)
    quantity_on_hand: Mapped[int] = mapped_column(Integer, default=0)
