"""Add user_facts table for accumulated user knowledge

Revision ID: 008
Revises: 007
Create Date: 2026-03-07
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "008"
down_revision = "007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_facts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("key", sa.String(256), nullable=False),
        sa.Column("value", sa.Text, nullable=False),
        sa.Column("category", sa.String(32), nullable=False, server_default="general"),
        sa.Column("source", sa.String(32), server_default="extracted", nullable=False),
        sa.Column("confidence", sa.Float, server_default="0.8", nullable=False),
        sa.Column("hit_count", sa.Integer, server_default="0", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(),
                  onupdate=sa.func.now()),
        sa.UniqueConstraint("user_id", "key", name="uq_user_facts_user_key"),
    )
    op.create_index("ix_user_facts_user_id", "user_facts", ["user_id"])
    op.create_index("ix_user_facts_user_category", "user_facts", ["user_id", "category"])


def downgrade() -> None:
    op.drop_table("user_facts")
