"""
main.py — FastAPI application entry point.

LIFESPAN PATTERN (replaces deprecated @app.on_event):
FastAPI 0.93+ uses lifespan context managers for startup/shutdown logic.
This is cleaner than on_event handlers and works properly with async.

STARTUP SEQUENCE:
1. Configure structured logging (loguru)
2. Warm up singletons (VectorStoreManager, RAGPipeline, RagasRunner)
   — these load the 90MB embedding model; do it at startup, not per-request
3. Verify DB connectivity
4. Log config summary

SHUTDOWN:
1. Dispose DB connection pool (graceful in-flight request completion)
"""

import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from loguru import logger
from sqlalchemy import text

from backend.config import get_settings
from backend.database import engine, get_db_context
from backend.rag.pipeline import get_pipeline
from backend.rag.vectorstore import get_vector_store
from backend.evaluator.ragas_runner import get_ragas_runner

settings = get_settings()


def configure_logging() -> None:
    """
    Configure loguru for structured JSON logging in production,
    human-readable colored output in development.
    
    WHY LOGURU OVER STDLIB LOGGING:
    - Zero config for colored output
    - Structured JSON mode for log aggregation (Datadog, Loki)
    - Better exception formatting with full stack traces
    - Lazy string formatting (f-strings only evaluated if log level matches)
    """
    logger.remove()  # remove default handler

    if settings.is_production:
        # JSON format for log aggregation pipelines
        logger.add(
            sys.stdout,
            format="{time:ISO8601} | {level} | {name}:{line} | {message}",
            level=settings.log_level,
            serialize=True,  # outputs JSON
        )
    else:
        # Human-readable with colors for development
        logger.add(
            sys.stdout,
            format=(
                "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
                "<level>{level: <8}</level> | "
                "<cyan>{name}</cyan>:<cyan>{line}</cyan> | "
                "<level>{message}</level>"
            ),
            level=settings.log_level,
            colorize=True,
        )

    # Also log to rotating file for persistence
    logger.add(
        "logs/verirag.log",
        rotation="100 MB",
        retention="30 days",
        compression="gz",
        level="INFO",
        enqueue=True,  # async file writing — doesn't block event loop
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    FastAPI lifespan: code before yield runs on startup, after yield on shutdown.
    
    WHY WARM UP SINGLETONS HERE:
    The embedding model (SentenceTransformer) takes ~2s to load from disk.
    If we initialize lazily (on first request), the first user gets a slow response.
    Pre-warming at startup gives consistent response times.
    """
    # ── Startup ───────────────────────────────────────────────────────────────
    configure_logging()
    import os
    os.makedirs("logs", exist_ok=True)

    logger.info("=" * 60)
    logger.info(f"VeriRAG starting | env={settings.app_env} | log={settings.log_level}")
    logger.info(f"Groq model: {settings.groq_model}")
    logger.info(f"Embedding model: {settings.embedding_model}")

    # Warm up the embedding model (loads ~90MB model weights)
    logger.info("Warming up embedding model...")
    try:
        vs = get_vector_store()
        logger.info("VectorStore initialized ✓")
    except Exception as e:
        logger.error(f"VectorStore initialization failed: {e}")

    # Warm up RAG pipeline (creates LangChain LLM client)
    logger.info("Warming up RAG pipeline...")
    try:
        pipeline = get_pipeline()
        logger.info("RAG pipeline initialized ✓")
    except Exception as e:
        logger.error(f"RAG pipeline initialization failed: {e}")

    # Warm up RAGAS runner
    logger.info("Warming up RAGAS runner...")
    try:
        runner = get_ragas_runner()
        logger.info("RAGAS runner initialized ✓")
    except Exception as e:
        logger.error(f"RAGAS runner initialization failed: {e}")

    # Verify DB connectivity
    logger.info("Checking database connectivity...")
    try:
        async with get_db_context() as db:
            await db.execute(text("SELECT 1"))
        logger.info("PostgreSQL connected ✓")
    except Exception as e:
        logger.error(f"Database connection failed: {e}")

    logger.info("VeriRAG startup complete ✓")
    logger.info("=" * 60)

    yield  # ── Application runs here ──────────────────────────────────────────

    # ── Shutdown ──────────────────────────────────────────────────────────────
    logger.info("VeriRAG shutting down...")
    await engine.dispose()
    logger.info("Database connection pool disposed ✓")
    logger.info("Shutdown complete.")


# ── FastAPI Application ────────────────────────────────────────────────────────

app = FastAPI(
    title="VeriRAG",
    description="""
## VeriRAG — Production RAG Evaluation & Observability Platform

VeriRAG evaluates RAG pipeline quality using [RAGAS](https://docs.ragas.io) metrics:

| Metric | Measures |
|--------|----------|
| **Faithfulness** | Is the answer grounded in retrieved context? (no hallucination) |
| **Answer Relevancy** | Does the answer address the question asked? |
| **Context Precision** | Are useful chunks ranked higher in retrieval? |
| **Context Recall** | Does retrieved context cover all ground truth information? |

### Quick Start
1. `POST /api/v1/pipeline/ingest` — upload your documents
2. `POST /api/v1/eval/run/sample` — run built-in sample evaluation
3. `GET /api/v1/eval/runs/{id}` — retrieve RAGAS scores from PostgreSQL
    """,
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# ── Middleware ─────────────────────────────────────────────────────────────────

# CORS: allow all origins in dev, restrict in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if not settings.is_production else ["https://yourdomain.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# GZip: compress responses > 1KB — especially useful for large eval results
app.add_middleware(GZipMiddleware, minimum_size=1000)

# ── Routers ───────────────────────────────────────────────────────────────────

from backend.routers import health, eval, pipeline  # noqa: E402

app.include_router(health.router)                                    # /health
app.include_router(eval.router, prefix=settings.api_v1_prefix)      # /api/v1/eval/...
app.include_router(pipeline.router, prefix=settings.api_v1_prefix)  # /api/v1/pipeline/...

# ── Root ──────────────────────────────────────────────────────────────────────

@app.get("/", include_in_schema=False)
async def root():
    return {
        "service": "VeriRAG",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health",
        "api": settings.api_v1_prefix,
    }
