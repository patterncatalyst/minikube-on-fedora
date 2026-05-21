"""SQLAlchemy declarative base for notification-service.

r22 skeleton: no tables yet. The service's schema (`notifications`) is created
at startup (see db.init_schema), ready for domain tables in a later
iteration. When this service's domain model lands, add table classes here
bound to `settings.service_schema` to keep the per-service ownership boundary
(CAP-003) explicit, e.g.:

    class Widget(Base):
        __tablename__ = "widgets"
        __table_args__ = {"schema": settings.service_schema}
        ...
"""

from __future__ import annotations

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
