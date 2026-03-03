"""Add apns_device_token column to users table."""

from alembic import op
import sqlalchemy as sa

revision = "007"
down_revision = "006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("apns_device_token", sa.String(128), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "apns_device_token")
