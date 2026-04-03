"""add analysis_status and celery_task_id to repair_estimates

Revision ID: 2c7d9a1b4e5f
Revises: eff281e40543
Create Date: 2026-03-27

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "2c7d9a1b4e5f"
down_revision: Union[str, Sequence[str], None] = "eff281e40543"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "repair_estimates",
        sa.Column(
            "analysis_status",
            sa.String(length=32),
            nullable=False,
            server_default="pending",
        ),
    )
    op.add_column(
        "repair_estimates",
        sa.Column("celery_task_id", sa.String(length=128), nullable=True),
    )
    op.create_index(
        op.f("ix_repair_estimates_celery_task_id"),
        "repair_estimates",
        ["celery_task_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_repair_estimates_celery_task_id"), table_name="repair_estimates")
    op.drop_column("repair_estimates", "celery_task_id")
    op.drop_column("repair_estimates", "analysis_status")
