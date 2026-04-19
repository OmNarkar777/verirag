"""Add regression tracking and LangSmith URL to eval_runs

Revision ID: 002_add_regression_fields
Revises: 001_initial_schema
Create Date: 2024-06-01 00:00:00.000000

WHY THESE COLUMNS:
- has_regression: Boolean with index — enables O(1) "show all regressions"
  query without recomputing score deltas at query time
- regression_details: JSONB — stores the full per-metric diff so the
  dashboard can display "faithfulness: 0.87 -> 0.71" without re-querying
- compared_to_run_id: FK to previous run — audit trail of what was compared
- langsmith_run_url: direct link to trace page — embeds observability into
  every eval record
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "002_add_regression_fields"
down_revision = "001_initial_schema"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "eval_runs",
        sa.Column(
            "has_regression",
            sa.Boolean(),
            nullable=False,
            server_default="false",
            comment="True if any metric dropped >threshold vs previous run",
        ),
    )
    op.add_column(
        "eval_runs",
        sa.Column(
            "regression_details",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default="{}",
            comment="Per-metric delta: {metric: {prev, curr, delta, is_regression}}",
        ),
    )
    op.add_column(
        "eval_runs",
        sa.Column(
            "compared_to_run_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("eval_runs.id", ondelete="SET NULL"),
            nullable=True,
            comment="Previous run this was compared against for regression detection",
        ),
    )
    op.add_column(
        "eval_runs",
        sa.Column(
            "langsmith_run_url",
            sa.VARCHAR(500),
            nullable=True,
            comment="LangSmith project URL for trace inspection",
        ),
    )

    # Index for fast regression dashboard queries
    op.create_index(
        "ix_eval_runs_has_regression",
        "eval_runs",
        ["has_regression"],
        postgresql_where=sa.text("has_regression = true"),  # partial index
    )


def downgrade() -> None:
    op.drop_index("ix_eval_runs_has_regression", table_name="eval_runs")
    op.drop_column("eval_runs", "langsmith_run_url")
    op.drop_column("eval_runs", "compared_to_run_id")
    op.drop_column("eval_runs", "regression_details")
    op.drop_column("eval_runs", "has_regression")
