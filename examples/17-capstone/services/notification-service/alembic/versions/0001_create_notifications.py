"""create notifications table

Revision ID: 0001_create_notifications
Revises:
Create Date: 2026-05-22

The first migration for notification-service. Creates the `notifications`
table in the service's own `notifications` schema (CAP-003). The schema itself
is ensured by env.py before this runs.

Note (Alembic async): upgrade()/downgrade() are plain *sync* functions even
though the engine is async — Alembic runs them inside `connection.run_sync`,
so `op.*` works normally and must not be awaited (per Alembic discussion #1208).
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0001_create_notifications"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "notifications"


def upgrade() -> None:
    op.create_table(
        "notifications",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("order_id", sa.String(), nullable=False),
        sa.Column("event_type", sa.String(), nullable=False),
        sa.Column("customer_id", sa.String(), nullable=True),
        sa.Column("item_sku", sa.String(), nullable=True),
        sa.Column("quantity", sa.Integer(), nullable=True),
        sa.Column("amount", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name="pk_notifications"),
        sa.UniqueConstraint("order_id", name="uq_notifications_order_id"),
        schema=SCHEMA,
    )


def downgrade() -> None:
    op.drop_table("notifications", schema=SCHEMA)
