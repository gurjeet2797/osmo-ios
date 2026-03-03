"""Add indexed_events and proactive_notifications tables for intelligent data indexing

Revision ID: 005
Revises: 004
Create Date: 2026-03-02
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "005"
down_revision = "004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "indexed_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("source", sa.String(64), nullable=False),
        sa.Column("source_id", sa.String(256), nullable=False),
        sa.Column("event_type", sa.String(64), nullable=False),
        sa.Column("title", sa.String(512), nullable=False),
        sa.Column("details", postgresql.JSONB, server_default="{}"),
        sa.Column("event_date", sa.DateTime(timezone=True), nullable=False),
        sa.Column("location", sa.String(512), nullable=True),
        sa.Column("indexed_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("notified", sa.Boolean, server_default="false"),
        sa.UniqueConstraint("user_id", "source", "source_id", name="uq_indexed_events_user_source"),
    )
    op.create_index("ix_indexed_events_user_id", "indexed_events", ["user_id"])
    op.create_index("ix_indexed_events_event_date", "indexed_events", ["event_date"])

    op.create_table(
        "proactive_notifications",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("event_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("indexed_events.id", ondelete="SET NULL"), nullable=True),
        sa.Column("title", sa.String(256), nullable=False),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("suggested_actions", postgresql.JSONB, server_default="[]"),
        sa.Column("fire_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("delivered", sa.Boolean, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_proactive_notifications_user_id", "proactive_notifications", ["user_id"])
    op.create_index("ix_proactive_notifications_fire_at", "proactive_notifications", ["fire_at"])


def downgrade() -> None:
    op.drop_table("proactive_notifications")
    op.drop_table("indexed_events")
