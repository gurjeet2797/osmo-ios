"""Add subscription_tier column to users table

Revision ID: 006
Revises: 005
Create Date: 2026-03-03
"""

from alembic import op
import sqlalchemy as sa

revision = "006"
down_revision = "005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("subscription_tier", sa.String(16), server_default="free", nullable=False),
    )


def downgrade() -> None:
    op.drop_column("users", "subscription_tier")
