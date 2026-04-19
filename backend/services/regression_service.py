"""
services/regression_service.py — Regression detection engine.

THE KEY DIFFERENTIATOR:
Any junior engineer can run RAGAS once. This service catches when a pipeline
CHANGE caused quality to REGRESS — comparing the current run's scores against
the most recent previous completed run and flagging metric drops that exceed
the configured threshold.

WHY THIS MATTERS IN PRODUCTION:
A RAG pipeline goes through many iterations: new chunking strategy, different
embedding model, prompt tweaks, retriever changes. Without regression tracking,
a change that improves context_recall might silently tank faithfulness. This
service makes that visible immediately when the eval completes.

REGRESSION DEFINITION:
  delta = current_score - previous_score
  regression triggered when: delta <= -threshold  (absolute drop)

Example: faithfulness 0.87 -> 0.71 = delta -0.16 > threshold 0.10 → REGRESSION

DESIGN: runs synchronously inside _complete_eval_run() after scores are stored.
No separate job or queue needed — it's a fast comparison of 4 floats.
"""

import uuid
from datetime import datetime, timezone

from loguru import logger
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.config import get_settings
from backend.models import EvalRun

settings = get_settings()

METRIC_FIELDS = {
    "faithfulness": ("avg_faithfulness", "avg_faithfulness"),
    "answer_relevancy": ("avg_answer_relevancy", "avg_answer_relevancy"),
    "context_precision": ("avg_context_precision", "avg_context_precision"),
    "context_recall": ("avg_context_recall", "avg_context_recall"),
}


async def detect_and_store_regressions(
    db: AsyncSession,
    current_run_id: uuid.UUID,
) -> dict:
    """
    Compare current completed run against the most recent previous completed run.

    Stores results directly on the EvalRun record:
      - has_regression: bool (fast dashboard filter)
      - regression_details: JSONB (structured diff for UI display)
      - compared_to_run_id: UUID (audit trail)

    Returns the regression_details dict for logging / API response.
    """
    # Load the current run
    result = await db.execute(select(EvalRun).where(EvalRun.id == current_run_id))
    current = result.scalar_one_or_none()
    if not current:
        logger.warning(f"Regression check: run {current_run_id} not found")
        return {}

    # Find the most recent OTHER completed run — regardless of version tag
    # WHY: we compare consecutive runs, not same-version runs. You want to know
    # if YOUR LAST CHANGE broke anything.
    prev_result = await db.execute(
        select(EvalRun)
        .where(
            EvalRun.status == "completed",
            EvalRun.id != current_run_id,
        )
        .order_by(desc(EvalRun.completed_at))
        .limit(1)
    )
    previous = prev_result.scalar_one_or_none()

    if not previous:
        logger.info(f"Regression check: no previous run to compare against (run_id={current_run_id})")
        return {}

    # Compare each metric
    regressions: dict[str, dict] = {}
    threshold = settings.regression_threshold

    metric_map = {
        "faithfulness": (current.avg_faithfulness, previous.avg_faithfulness),
        "answer_relevancy": (current.avg_answer_relevancy, previous.avg_answer_relevancy),
        "context_precision": (current.avg_context_precision, previous.avg_context_precision),
        "context_recall": (current.avg_context_recall, previous.avg_context_recall),
    }

    for metric_name, (curr_val, prev_val) in metric_map.items():
        if curr_val is None or prev_val is None:
            # Can't compare if either run didn't produce a score for this metric
            continue

        delta = curr_val - prev_val

        entry = {
            "previous": round(prev_val, 4),
            "current": round(curr_val, 4),
            "delta": round(delta, 4),
            "threshold": threshold,
            "is_regression": delta <= -threshold,
        }

        if entry["is_regression"]:
            regressions[metric_name] = entry
            logger.warning(
                f"REGRESSION DETECTED | metric={metric_name} | "
                f"{prev_val:.3f} -> {curr_val:.3f} (delta={delta:.3f}) | "
                f"run_id={current_run_id} | compared_to={previous.id}"
            )
        else:
            # Store all deltas, not just regressions — useful for trend display
            entry["is_regression"] = False
            regressions[metric_name] = entry

    has_regression = any(v["is_regression"] for v in regressions.values())

    # Persist to DB
    current.has_regression = has_regression
    current.regression_details = regressions
    current.compared_to_run_id = previous.id

    if has_regression:
        flagged = [m for m, v in regressions.items() if v["is_regression"]]
        logger.warning(
            f"Eval run {current_run_id} has REGRESSIONS in: {flagged} "
            f"(compared to {previous.version_tag})"
        )
    else:
        logger.info(
            f"Eval run {current_run_id} — no regressions vs {previous.version_tag}"
        )

    return regressions
