"""Create accounts, sessions and contacts."""
import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "hollow_users",
        sa.Column("username", sa.String(32), primary_key=True),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("password_hash", sa.String(128), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=False, unique=True),
        sa.CheckConstraint("level IN (2, 3, 4)", name="hollow_user_level"),
    )
    op.create_table(
        "hollow_sessions",
        sa.Column("token_hash", sa.String(64), primary_key=True),
        sa.Column("username", sa.String(32), sa.ForeignKey("hollow_users.username", ondelete="CASCADE"), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_hollow_sessions_username", "hollow_sessions", ["username"])
    op.create_table(
        "hollow_contacts",
        sa.Column("owner", sa.String(32), sa.ForeignKey("hollow_users.username", ondelete="CASCADE"), primary_key=True),
        sa.Column("contact", sa.String(32), sa.ForeignKey("hollow_users.username", ondelete="CASCADE"), primary_key=True),
    )
    if op.get_context().dialect.name == "postgresql":
        for table in ("hollow_users", "hollow_sessions", "hollow_contacts", "hollow_alembic_version"):
            op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")


def downgrade():
    op.drop_table("hollow_contacts")
    op.drop_table("hollow_sessions")
    op.drop_table("hollow_users")
