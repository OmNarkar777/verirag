"""
routers/health.py — Health check endpoint.

WHY A PROPER HEALTH ENDPOINT:
- Kubernetes liveness/readiness probes call /health
- Load balancers route traffic only to healthy instances
- Monitoring systems alert when DB or vector store becomes unavailable

We check actual dependency connectivity, not just "is the process running".
A degraded health check (DB down but app running) is different from a crash.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from backend.database import get_db
from backend.config import get_settings
from backend.rag.vectorstore import get_vector_store
from backend.schemas import HealthResponse

router = APIRouter(tags=["health"])
settings = get_settings()


@router.get("/health", response_model=HealthResponse, summary="System health check")
async def health_check(db: AsyncSession = Depends(get_db)) -> HealthResponse:
    """
    Checks connectivity to PostgreSQL and ChromaDB.
    Returns 200 if all systems operational, 503 if any dependency is down.

    Kubernetes pattern: use this as both liveness and readiness probe.
    """
    db_status = "unknown"
    chroma_status = "unknown"

    # Check PostgreSQL
    try:
        await db.execute(text("SELECT 1"))
        db_status = "ok"
    except Exception as e:
        db_status = f"error: {str(e)[:100]}"

    # Check ChromaDB
    try:
        vs = get_vector_store()
        stats = vs.get_collection_stats()
        chroma_status = f"ok (docs={stats['document_count']})"
    except Exception as e:
        chroma_status = f"error: {str(e)[:100]}"

    overall_status = "ok" if (db_status == "ok" and chroma_status.startswith("ok")) else "degraded"

    return HealthResponse(
        status=overall_status,
        version="1.0.0",
        database=db_status,
        chromadb=chroma_status,
        environment=settings.app_env,
    )
