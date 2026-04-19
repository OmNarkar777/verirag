# VeriRAG — Complete Fix Script
# Run from PowerShell in ANY directory. Sets its own base path.
# Usage: powershell -ExecutionPolicy Bypass -File verirag_fix.ps1

$BASE = "C:\Users\Om\Desktop\Leadflow_ai\v2\PROJECTS\VeriRAG"
$ErrorActionPreference = "Stop"

function wf($rel, $content) {
    $p = Join-Path $BASE $rel
    $d = Split-Path $p -Parent
    if (!(Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [System.IO.File]::WriteAllText($p, $content, [System.Text.Encoding]::UTF8)
    Write-Host "  FIXED  $rel"
}
Write-Host "`n=== VeriRAG Fix Script ===" -ForegroundColor Cyan
Write-Host "Base: $BASE`n"

# ─────────────────────────────────────────────────────────────
# FIX 1 — config.py  (langchain optional, add regression/rate settings)
# ─────────────────────────────────────────────────────────────
$f01 = @'
"""config.py — Centralized settings via pydantic-settings."""
from functools import lru_cache
from pydantic import Field, computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # LLM
    groq_api_key: str = Field(..., description="Groq API key")
    groq_model: str = Field(default="llama-3.3-70b-versatile")
    groq_temperature: float = Field(default=0.0)

    # Observability — optional so app starts without LangSmith
    langchain_api_key: str = Field(default="", description="LangSmith API key (optional)")
    langchain_tracing_v2: bool = Field(default=False)
    langchain_project: str = Field(default="verirag-prod")

    # Database
    database_url: str = Field(..., description="postgresql+asyncpg:// required")

    # ChromaDB
    chroma_persist_dir: str = Field(default="./chroma_data")
    chroma_collection_name: str = Field(default="verirag_docs")

    # Embeddings
    embedding_model: str = Field(default="all-MiniLM-L6-v2")

    # RAG
    retrieval_top_k: int = Field(default=5)
    retrieval_lambda: float = Field(default=0.5)

    # Regression detection — 0.10 = 10-point absolute drop triggers flag
    regression_threshold: float = Field(default=0.10)

    # Rate limiting — each RAGAS run makes ~200 Groq calls; cap concurrency
    max_concurrent_evals: int = Field(default=5)

    # App
    app_env: str = Field(default="development")
    log_level: str = Field(default="DEBUG")
    api_v1_prefix: str = Field(default="/api/v1")

    @computed_field
    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
'@
wf "backend\config.py" $f01

# ─────────────────────────────────────────────────────────────
# FIX 2 — models.py  (add regression + LangSmith fields)
# ─────────────────────────────────────────────────────────────
$f02 = @'
"""models.py — SQLAlchemy ORM models for VeriRAG (Phase 2)."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    ARRAY, TIMESTAMP, Boolean, VARCHAR,
    Float, ForeignKey, Integer, Text, UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class EvalRun(Base):
    __tablename__ = "eval_runs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    version_tag: Mapped[str] = mapped_column(VARCHAR(100), nullable=False, index=True)
    pipeline_name: Mapped[str] = mapped_column(VARCHAR(200), nullable=False)
    status: Mapped[str] = mapped_column(VARCHAR(20), nullable=False, default="pending")
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False, default=utcnow)
    completed_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True), nullable=True)
    total_cases: Mapped[int] = mapped_column(Integer, default=0)

    avg_faithfulness: Mapped[float | None] = mapped_column(Float, nullable=True)
    avg_answer_relevancy: Mapped[float | None] = mapped_column(Float, nullable=True)
    avg_context_precision: Mapped[float | None] = mapped_column(Float, nullable=True)
    avg_context_recall: Mapped[float | None] = mapped_column(Float, nullable=True)

    run_metadata: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Phase 2: regression tracking
    has_regression: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)
    regression_details: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    compared_to_run_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("eval_runs.id", ondelete="SET NULL", use_alter=True, name="fk_eval_run_compared_to"),
        nullable=True,
    )
    langsmith_run_url: Mapped[str | None] = mapped_column(VARCHAR(500), nullable=True)

    cases: Mapped[list["EvalCase"]] = relationship(
        "EvalCase", back_populates="eval_run",
        cascade="all, delete-orphan", lazy="selectin",
    )


class EvalCase(Base):
    __tablename__ = "eval_cases"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    eval_run_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("eval_runs.id", ondelete="CASCADE"), nullable=False, index=True
    )
    question: Mapped[str] = mapped_column(Text, nullable=False)
    answer: Mapped[str] = mapped_column(Text, nullable=False)
    contexts: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)
    ground_truth: Mapped[str] = mapped_column(Text, nullable=False)

    faithfulness_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    answer_relevancy_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    context_precision_score: Mapped[float | None] = mapped_column(Float, nullable=True)
    context_recall_score: Mapped[float | None] = mapped_column(Float, nullable=True)

    created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False, default=utcnow)
    eval_run: Mapped["EvalRun"] = relationship("EvalRun", back_populates="cases")


class PipelineDocument(Base):
    __tablename__ = "pipeline_documents"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    doc_id: Mapped[str] = mapped_column(VARCHAR(500), nullable=False)
    filename: Mapped[str] = mapped_column(VARCHAR(500), nullable=False)
    chunk_count: Mapped[int] = mapped_column(Integer, default=0)
    ingested_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), nullable=False, default=utcnow)
    collection_name: Mapped[str] = mapped_column(VARCHAR(200), nullable=False)
    doc_metadata: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    __table_args__ = (UniqueConstraint("doc_id", "collection_name", name="uq_doc_collection"),)
'@
wf "backend\models.py" $f02

# ─────────────────────────────────────────────────────────────
# FIX 3 — rag/pipeline.py  (correct method names + return keys)
# ─────────────────────────────────────────────────────────────
$f03 = @'
"""rag/pipeline.py — End-to-end RAG pipeline with correct interface for routers."""
import os
from typing import Optional
from loguru import logger

from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import ChatPromptTemplate
from langchain_groq import ChatGroq
from langsmith import traceable

from backend.config import get_settings
from backend.rag.vectorstore import VectorStoreManager, get_vector_store
from backend.rag.retriever import RAGRetriever

settings = get_settings()

RAG_SYSTEM_PROMPT = """You are a precise assistant. Answer ONLY from the provided context.
If the context lacks the answer, say so clearly. Do not use external knowledge.

Context:
{context}"""

RAG_HUMAN_PROMPT = "Question: {question}"


class RAGPipeline:
    def __init__(self, vectorstore: Optional[VectorStoreManager] = None):
        # Use 'vector_store' attribute — routers reference pipeline.vector_store
        self.vector_store = vectorstore or get_vector_store()
        self.retriever = RAGRetriever(vector_store=self.vector_store)

        # LangSmith env setup inside __init__ — avoids module-level import failures
        if settings.langchain_api_key:
            os.environ["LANGCHAIN_TRACING_V2"] = str(settings.langchain_tracing_v2).lower()
            os.environ["LANGCHAIN_API_KEY"] = settings.langchain_api_key
            os.environ["LANGCHAIN_PROJECT"] = settings.langchain_project

        self.llm = ChatGroq(
            api_key=settings.groq_api_key,
            model=settings.groq_model,         # 'model' not 'model_name'
            temperature=settings.groq_temperature,
        )
        self.prompt = ChatPromptTemplate.from_messages([
            ("system", RAG_SYSTEM_PROMPT),
            ("human", RAG_HUMAN_PROMPT),
        ])
        self.chain = self.prompt | self.llm | StrOutputParser()

    @traceable(name="rag_pipeline_query", run_type="chain")
    def query(
        self,
        question: str,
        collection_name: Optional[str] = None,
        top_k: Optional[int] = None,
    ) -> dict:
        """
        Returns dict with keys:
          question, answer, retrieved_chunks (list of dicts), model_used
        These keys match exactly what routers/pipeline.py expects.
        """
        logger.info(f"RAG query | question={question[:80]}")

        # Use keyword args — avoids positional-arg bug (top_k passed as collection_name)
        chunks = self.retriever.retrieve(
            query=question,
            collection_name=collection_name,
            top_k=top_k,
            use_mmr=True,
        )

        if not chunks:
            logger.warning("No chunks retrieved")
            return {
                "question": question,
                "answer": "I don't have enough context to answer this question.",
                "retrieved_chunks": [],
                "model_used": settings.groq_model,
            }

        context_str = "\n\n".join(
            f"[Chunk {i+1} from {c['source']}]:\n{c['content']}"
            for i, c in enumerate(chunks)
        )

        answer = self.chain.invoke({"context": context_str, "question": question})

        logger.info(f"RAG response | chunks={len(chunks)} | answer_len={len(answer)}")
        return {
            "question": question,
            "answer": answer,
            "retrieved_chunks": chunks,      # list of {content, source, score, metadata}
            "model_used": settings.groq_model,
        }

    def ingest_text(
        self,
        text: str,
        filename: str,
        collection_name: Optional[str] = None,
    ) -> dict:
        """Delegate to vectorstore — accepts collection_name for router compatibility."""
        return self.vector_store.ingest_text(
            text=text, filename=filename, collection_name=collection_name
        )

    def ingest_pdf(self, file_path: str, collection_name: Optional[str] = None) -> dict:
        """Delegate to vectorstore."""
        return self.vector_store.ingest_pdf(
            file_path=file_path, collection_name=collection_name
        )


_pipeline: Optional[RAGPipeline] = None


def get_pipeline() -> RAGPipeline:
    global _pipeline
    if _pipeline is None:
        _pipeline = RAGPipeline()
    return _pipeline
'@
wf "backend\rag\pipeline.py" $f03

# ─────────────────────────────────────────────────────────────
# FIX 4 — schemas.py  (append regression schemas at end)
# ─────────────────────────────────────────────────────────────
$f04 = @'
"""schemas.py — Pydantic v2 request/response schemas."""
import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field, field_validator, model_validator


class TestCaseInput(BaseModel):
    question: str = Field(..., min_length=5)
    answer: str = Field(..., min_length=1)
    contexts: list[str] = Field(..., min_length=1)
    ground_truth: str = Field(..., min_length=1)

    @field_validator("contexts")
    @classmethod
    def contexts_must_have_content(cls, v: list[str]) -> list[str]:
        if any(not ctx.strip() for ctx in v):
            raise ValueError("All context strings must be non-empty")
        return v


class EvalRunRequest(BaseModel):
    version_tag: str = Field(..., pattern=r"^v\d+\.\d+\.\d+.*$")
    pipeline_name: str = Field(..., min_length=1, max_length=200)
    test_cases: list[TestCaseInput] = Field(..., min_length=1)
    metadata: dict[str, Any] = Field(default_factory=dict)


class MetricScores(BaseModel):
    faithfulness: float | None = Field(None, ge=0.0, le=1.0)
    answer_relevancy: float | None = Field(None, ge=0.0, le=1.0)
    context_precision: float | None = Field(None, ge=0.0, le=1.0)
    context_recall: float | None = Field(None, ge=0.0, le=1.0)


class EvalCaseResult(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    question: str
    answer: str
    contexts: list[str]
    ground_truth: str
    faithfulness_score: float | None
    answer_relevancy_score: float | None
    context_precision_score: float | None
    context_recall_score: float | None
    created_at: datetime


class EvalRunResponse(BaseModel):
    eval_run_id: uuid.UUID
    version_tag: str
    status: str
    message: str = "Evaluation started in background"


class EvalRunSummary(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    version_tag: str
    pipeline_name: str
    status: str
    created_at: datetime
    completed_at: datetime | None
    total_cases: int
    scores: MetricScores | None = None


class EvalRunDetail(EvalRunSummary):
    cases: list[EvalCaseResult] = Field(default_factory=list)
    run_metadata: dict[str, Any] = Field(default_factory=dict)
    error_message: str | None = None


# ── Pipeline ──────────────────────────────────────────────────────────────────
class QueryRequest(BaseModel):
    question: str = Field(..., min_length=5)
    top_k: int = Field(default=5, ge=1, le=20)
    collection_name: str | None = None


class RetrievedChunk(BaseModel):
    content: str
    source: str
    score: float
    metadata: dict[str, Any] = Field(default_factory=dict)


class QueryResponse(BaseModel):
    question: str
    answer: str
    retrieved_chunks: list[RetrievedChunk]
    model_used: str
    langsmith_trace_url: str | None = None


class IngestResponse(BaseModel):
    doc_id: str
    filename: str
    chunks_created: int
    collection_name: str
    message: str


class HealthResponse(BaseModel):
    status: str
    version: str
    database: str
    chromadb: str
    environment: str


class PaginatedCases(BaseModel):
    total: int
    page: int
    page_size: int
    cases: list[EvalCaseResult]


# ── Regression (Phase 2) ──────────────────────────────────────────────────────
class MetricDelta(BaseModel):
    previous: float
    current: float
    delta: float
    threshold: float
    is_regression: bool


class RegressionSummary(BaseModel):
    has_regression: bool
    compared_to_run_id: Any | None = None
    metrics: dict[str, MetricDelta] = Field(default_factory=dict)


class EvalRunWithRegression(EvalRunSummary):
    """EvalRunSummary extended with regression info."""
    has_regression: bool = False
    regression_details: dict[str, Any] = Field(default_factory=dict)
    compared_to_run_id: Any | None = None
    langsmith_run_url: str | None = None
'@
wf "backend\schemas.py" $f04

# ─────────────────────────────────────────────────────────────
# FIX 5 — routers/eval.py  (semaphore + /regressions + /status)
# ─────────────────────────────────────────────────────────────
$f05 = @'
"""routers/eval.py — Evaluation endpoints with rate limiting and regression detection."""
import asyncio
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from loguru import logger
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.config import get_settings
from backend.database import get_db
from backend.models import EvalRun
from backend.schemas import (
    EvalRunDetail, EvalRunRequest, EvalRunResponse,
    EvalRunWithRegression, MetricScores, PaginatedCases,
)
from backend.services.eval_service import EvalService, get_eval_service

router = APIRouter(prefix="/eval", tags=["evaluation"])
settings = get_settings()

# Semaphore: hard cap on concurrent RAGAS evals.
# Each run makes ~200 Groq API calls. >5 concurrent = cascading rate-limit failures.
_eval_semaphore = asyncio.Semaphore(settings.max_concurrent_evals)
_active_evals = 0  # track count without accessing private _value


async def _guarded_execution(service, eval_run_id, test_cases) -> None:
    global _active_evals
    async with _eval_semaphore:
        _active_evals += 1
        try:
            await service.execute_evaluation(eval_run_id, test_cases)
        finally:
            _active_evals -= 1


@router.post("/run", response_model=EvalRunResponse, status_code=202)
async def start_eval_run(
    request: EvalRunRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    service: EvalService = Depends(get_eval_service),
) -> EvalRunResponse:
    logger.info(f"POST /eval/run | version={request.version_tag} | cases={len(request.test_cases)}")
    eval_run_id = await service.start_eval_run(
        db=db,
        version_tag=request.version_tag,
        pipeline_name=request.pipeline_name,
        test_cases=request.test_cases,
        metadata=request.metadata,
    )
    background_tasks.add_task(_guarded_execution, service, eval_run_id, request.test_cases)
    return EvalRunResponse(
        eval_run_id=eval_run_id,
        version_tag=request.version_tag,
        status="running",
        message=f"Evaluation started ({len(request.test_cases)} cases). Poll GET /api/v1/eval/runs/{eval_run_id}",
    )


@router.post("/run/sample", response_model=EvalRunResponse, status_code=202)
async def run_sample_eval(
    background_tasks: BackgroundTasks,
    version_tag: str = Query(default="v0.0.1-sample", pattern=r"^v\d+\.\d+\.\d+.*$"),
    db: AsyncSession = Depends(get_db),
    service: EvalService = Depends(get_eval_service),
) -> EvalRunResponse:
    from backend.evaluator.dataset_builder import get_sample_test_cases
    test_cases = get_sample_test_cases()
    eval_run_id = await service.start_eval_run(
        db=db, version_tag=version_tag, pipeline_name="sample-ai-ml-pipeline",
        test_cases=test_cases, metadata={"dataset": "sample_10_ai_ml_cases", "source": "builtin"},
    )
    background_tasks.add_task(_guarded_execution, service, eval_run_id, test_cases)
    return EvalRunResponse(
        eval_run_id=eval_run_id, version_tag=version_tag, status="running",
        message=f"Sample evaluation started ({len(test_cases)} cases). Poll GET /api/v1/eval/runs/{eval_run_id}",
    )


@router.get("/runs", response_model=list[EvalRunWithRegression])
async def list_eval_runs(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
) -> list[EvalRunWithRegression]:
    result = await db.execute(
        select(EvalRun).order_by(EvalRun.created_at.desc()).limit(limit).offset(offset)
    )
    runs = result.scalars().all()
    return [_run_to_regression_schema(r) for r in runs]


@router.get("/runs/{run_id}", response_model=EvalRunDetail)
async def get_eval_run(
    run_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    service: EvalService = Depends(get_eval_service),
) -> EvalRunDetail:
    run = await service.get_eval_run(db=db, run_id=run_id)
    if not run:
        raise HTTPException(status_code=404, detail=f"Eval run {run_id} not found")
    return run


@router.get("/runs/{run_id}/cases", response_model=PaginatedCases)
async def get_eval_cases(
    run_id: uuid.UUID,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    service: EvalService = Depends(get_eval_service),
) -> PaginatedCases:
    result = await service.get_eval_cases_paginated(db=db, run_id=run_id, page=page, page_size=page_size)
    if result is None:
        raise HTTPException(status_code=404, detail=f"Eval run {run_id} not found")
    return result


@router.get("/regressions", response_model=list[EvalRunWithRegression],
            summary="All eval runs where a metric dropped more than the threshold")
async def get_regressions(db: AsyncSession = Depends(get_db)) -> list[EvalRunWithRegression]:
    result = await db.execute(
        select(EvalRun)
        .where(EvalRun.has_regression == True)  # noqa: E712
        .order_by(EvalRun.created_at.desc())
        .limit(100)
    )
    runs = result.scalars().all()
    return [_run_to_regression_schema(r) for r in runs]


@router.get("/status", summary="Concurrency status")
async def eval_status() -> dict:
    return {
        "max_concurrent_evals": settings.max_concurrent_evals,
        "active_evals": _active_evals,
        "available_slots": settings.max_concurrent_evals - _active_evals,
        "regression_threshold": settings.regression_threshold,
    }


@router.delete("/runs/{run_id}", status_code=204)
async def delete_eval_run(run_id: uuid.UUID, db: AsyncSession = Depends(get_db)) -> None:
    result = await db.execute(select(EvalRun).where(EvalRun.id == run_id))
    run = result.scalar_one_or_none()
    if not run:
        raise HTTPException(status_code=404, detail=f"Eval run {run_id} not found")
    await db.delete(run)
    logger.info(f"Deleted eval run | id={run_id}")


def _run_to_regression_schema(r: EvalRun) -> EvalRunWithRegression:
    scores = MetricScores(
        faithfulness=r.avg_faithfulness,
        answer_relevancy=r.avg_answer_relevancy,
        context_precision=r.avg_context_precision,
        context_recall=r.avg_context_recall,
    ) if r.status == "completed" else None
    return EvalRunWithRegression(
        id=r.id, version_tag=r.version_tag, pipeline_name=r.pipeline_name,
        status=r.status, created_at=r.created_at, completed_at=r.completed_at,
        total_cases=r.total_cases, scores=scores,
        has_regression=r.has_regression,
        regression_details=r.regression_details or {},
        compared_to_run_id=r.compared_to_run_id,
        langsmith_run_url=r.langsmith_run_url,
    )
'@
wf "backend\routers\eval.py" $f05

# ─────────────────────────────────────────────────────────────
# FIX 6 — evaluator/ragas_runner.py  (LangchainLLMWrapper + regression)
# ─────────────────────────────────────────────────────────────
$f06 = @'
"""evaluator/ragas_runner.py — Core RAGAS evaluation engine with regression detection."""
import asyncio
import uuid
from datetime import datetime, timezone

from langchain_core.embeddings import Embeddings
from langchain_groq import ChatGroq
from loguru import logger
from ragas import evaluate
from ragas.metrics import AnswerRelevancy, ContextPrecision, ContextRecall, Faithfulness
from sentence_transformers import SentenceTransformer

from backend.config import get_settings
from backend.database import get_db_context
from backend.evaluator.dataset_builder import build_ragas_dataset
from backend.models import EvalCase, EvalRun
from backend.schemas import TestCaseInput

settings = get_settings()


class SentenceTransformerEmbeddings(Embeddings):
    """LangChain-compatible wrapper so RAGAS AnswerRelevancy can use our local model."""
    def __init__(self):
        self.model = SentenceTransformer(settings.embedding_model)

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return self.model.encode(texts, normalize_embeddings=True).tolist()

    def embed_query(self, text: str) -> list[float]:
        return self.model.encode([text], normalize_embeddings=True)[0].tolist()


class RagasRunner:
    def __init__(self):
        self.judge_llm = ChatGroq(
            api_key=settings.groq_api_key,
            model=settings.groq_model,
            temperature=0.0,
        )
        self.embeddings = SentenceTransformerEmbeddings()
        logger.info(f"RagasRunner initialized | judge_model={settings.groq_model}")

    def _configure_metrics(self) -> list:
        """
        Inject LLM into RAGAS metrics via LangchainLLMWrapper.
        Direct assignment of a raw ChatGroq fails in RAGAS 0.1.9+;
        wrapping is the correct integration pattern.
        """
        try:
            from ragas.llms import LangchainLLMWrapper
            from ragas.embeddings import LangchainEmbeddingsWrapper
            wrapped_llm = LangchainLLMWrapper(self.judge_llm)
            wrapped_emb = LangchainEmbeddingsWrapper(self.embeddings)
        except ImportError:
            # Older RAGAS version — direct assignment works
            wrapped_llm = self.judge_llm
            wrapped_emb = self.embeddings

        faithfulness = Faithfulness()
        faithfulness.llm = wrapped_llm

        answer_relevancy = AnswerRelevancy()
        answer_relevancy.llm = wrapped_llm
        answer_relevancy.embeddings = wrapped_emb

        context_precision = ContextPrecision()
        context_precision.llm = wrapped_llm

        context_recall = ContextRecall()
        context_recall.llm = wrapped_llm

        return [faithfulness, answer_relevancy, context_precision, context_recall]

    async def create_eval_run(self, version_tag, pipeline_name, total_cases, metadata) -> uuid.UUID:
        async with get_db_context() as db:
            run = EvalRun(
                version_tag=version_tag, pipeline_name=pipeline_name,
                status="running", total_cases=total_cases,
                run_metadata={
                    "groq_model": settings.groq_model,
                    "embedding_model": settings.embedding_model,
                    "retrieval_top_k": settings.retrieval_top_k,
                    **metadata,
                },
            )
            db.add(run)
            await db.flush()
            run_id = run.id
            logger.info(f"Created EvalRun | id={run_id} | version={version_tag}")
            return run_id

    async def run_evaluation(self, eval_run_id: uuid.UUID, test_cases: list[TestCaseInput]) -> None:
        logger.info(f"Starting RAGAS evaluation | run_id={eval_run_id} | cases={len(test_cases)}")
        try:
            dataset = build_ragas_dataset(test_cases)
            metrics = self._configure_metrics()

            logger.info("Running RAGAS evaluate() in thread pool — may take several minutes...")
            # get_running_loop() is correct inside async; get_event_loop() is deprecated 3.10+
            loop = asyncio.get_running_loop()
            result = await loop.run_in_executor(
                None, lambda: evaluate(dataset=dataset, metrics=metrics)
            )

            scores_df = result.to_pandas()
            logger.info(f"RAGAS evaluate() complete | shape={scores_df.shape}")

            await self._persist_cases(eval_run_id, test_cases, scores_df)
            await self._complete_eval_run(eval_run_id, scores_df)

            # Regression detection — non-fatal
            try:
                await self._run_regression_check(eval_run_id)
            except Exception as e:
                logger.warning(f"Regression check failed (non-fatal): {e}")

            # LangSmith tagging — non-fatal
            try:
                await self._tag_langsmith(eval_run_id)
            except Exception as e:
                logger.warning(f"LangSmith tagging failed (non-fatal): {e}")

        except Exception as e:
            logger.error(f"RAGAS evaluation failed | run_id={eval_run_id} | error={e}")
            await self._fail_eval_run(eval_run_id, str(e))
            raise

    async def _persist_cases(self, eval_run_id, test_cases, scores_df) -> None:
        async with get_db_context() as db:
            cases = []
            for i, tc in enumerate(test_cases):
                row = scores_df.iloc[i] if i < len(scores_df) else None

                def safe_score(col: str) -> float | None:
                    if row is None or col not in scores_df.columns:
                        return None
                    val = row[col]
                    try:
                        import math
                        f = float(val)
                        return None if math.isnan(f) else f
                    except (TypeError, ValueError):
                        return None

                cases.append(EvalCase(
                    eval_run_id=eval_run_id,
                    question=tc.question, answer=tc.answer,
                    contexts=tc.contexts, ground_truth=tc.ground_truth,
                    faithfulness_score=safe_score("faithfulness"),
                    answer_relevancy_score=safe_score("answer_relevancy"),
                    context_precision_score=safe_score("context_precision"),
                    context_recall_score=safe_score("context_recall"),
                ))
            db.add_all(cases)
            logger.info(f"Persisted {len(cases)} eval cases | run_id={eval_run_id}")

    async def _complete_eval_run(self, eval_run_id, scores_df) -> None:
        import numpy as np
        def mean_score(col):
            if col not in scores_df.columns:
                return None
            vals = scores_df[col].dropna()
            return float(np.mean(vals)) if len(vals) > 0 else None

        async with get_db_context() as db:
            from sqlalchemy import select
            result = await db.execute(select(EvalRun).where(EvalRun.id == eval_run_id))
            run = result.scalar_one_or_none()
            if not run:
                return
            run.status = "completed"
            run.completed_at = datetime.now(timezone.utc)
            run.avg_faithfulness = mean_score("faithfulness")
            run.avg_answer_relevancy = mean_score("answer_relevancy")
            run.avg_context_precision = mean_score("context_precision")
            run.avg_context_recall = mean_score("context_recall")

            from backend.services.langsmith_service import get_langsmith_service
            ls = get_langsmith_service()
            run.langsmith_run_url = ls.get_project_url()

            logger.info(
                f"EvalRun completed | id={eval_run_id} | "
                f"faithfulness={run.avg_faithfulness:.3f if run.avg_faithfulness else 'N/A'}"
            )

    async def _run_regression_check(self, eval_run_id: uuid.UUID) -> None:
        from backend.services.regression_service import detect_and_store_regressions
        from backend.database import AsyncSessionLocal
        async with AsyncSessionLocal() as db:
            try:
                await detect_and_store_regressions(db, eval_run_id)
                await db.commit()
            except Exception:
                await db.rollback()
                raise

    async def _tag_langsmith(self, eval_run_id: uuid.UUID) -> None:
        async with get_db_context() as db:
            from sqlalchemy import select
            result = await db.execute(select(EvalRun).where(EvalRun.id == eval_run_id))
            run = result.scalar_one_or_none()
            if not run:
                return
        from backend.services.langsmith_service import get_langsmith_service
        ls = get_langsmith_service()
        recent = ls.list_recent_traces(limit=5)
        tags = [f"eval_run:{str(eval_run_id)[:8]}", run.version_tag, run.pipeline_name]
        for trace in recent:
            ls.tag_run(trace["run_id"], tags)

    async def _fail_eval_run(self, eval_run_id: uuid.UUID, error: str) -> None:
        async with get_db_context() as db:
            from sqlalchemy import select
            result = await db.execute(select(EvalRun).where(EvalRun.id == eval_run_id))
            run = result.scalar_one_or_none()
            if run:
                run.status = "failed"
                run.completed_at = datetime.now(timezone.utc)
                run.error_message = error[:1000]
                logger.warning(f"EvalRun marked failed | id={eval_run_id}")


_runner: RagasRunner | None = None


def get_ragas_runner() -> RagasRunner:
    global _runner
    if _runner is None:
        _runner = RagasRunner()
    return _runner
'@
wf "backend\evaluator\ragas_runner.py" $f06

# ─────────────────────────────────────────────────────────────
# FIX 7 — langsmith_service.py  (guard empty API key)
# ─────────────────────────────────────────────────────────────
$f07 = @'
"""services/langsmith_service.py — LangSmith integration (gracefully disabled if no key)."""
from typing import Any
from loguru import logger
from backend.config import get_settings

settings = get_settings()


class LangSmithService:
    def __init__(self):
        self._client = None
        self._enabled = bool(settings.langchain_api_key) and settings.langchain_tracing_v2
        if self._enabled:
            try:
                from langsmith import Client
                self._client = Client(api_key=settings.langchain_api_key)
                logger.info(f"LangSmith connected | project={settings.langchain_project}")
            except Exception as e:
                logger.warning(f"LangSmith init failed (non-fatal): {e}")
                self._enabled = False

    @property
    def enabled(self) -> bool:
        return self._enabled and self._client is not None

    def get_project_url(self) -> str | None:
        if not self.enabled:
            return None
        return f"https://smith.langchain.com/projects/{settings.langchain_project}"

    def get_run_url(self, run_id: str) -> str | None:
        if not self.enabled:
            return None
        return f"https://smith.langchain.com/projects/{settings.langchain_project}/runs/{run_id}"

    def list_recent_traces(self, limit: int = 10) -> list[dict[str, Any]]:
        if not self.enabled or not self._client:
            return []
        try:
            runs = list(self._client.list_runs(
                project_name=settings.langchain_project, limit=limit, execution_order=1
            ))
            return [
                {
                    "run_id": str(r.id), "name": r.name, "status": r.status,
                    "start_time": r.start_time.isoformat() if r.start_time else None,
                    "url": self.get_run_url(str(r.id)),
                }
                for r in runs
            ]
        except Exception as e:
            logger.warning(f"Failed to fetch LangSmith traces: {e}")
            return []

    def tag_run(self, run_id: str, tags: list[str]) -> bool:
        if not self.enabled or not self._client:
            return False
        try:
            self._client.update_run(run_id=run_id, tags=tags)
            return True
        except Exception as e:
            logger.warning(f"Failed to tag LangSmith run {run_id}: {e}")
            return False


_langsmith_service: LangSmithService | None = None


def get_langsmith_service() -> LangSmithService:
    global _langsmith_service
    if _langsmith_service is None:
        _langsmith_service = LangSmithService()
    return _langsmith_service
'@
wf "backend\services\langsmith_service.py" $f07

# ─────────────────────────────────────────────────────────────
# FIX 8 — alembic/env.py  (proper offline/online mode)
# ─────────────────────────────────────────────────────────────
$f08 = @'
"""alembic/env.py — Async Alembic migration environment."""
import asyncio
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine
from dotenv import load_dotenv

load_dotenv()

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

from backend.database import Base          # noqa: E402
from backend.models import EvalRun, EvalCase, PipelineDocument  # noqa: E402, F401

target_metadata = Base.metadata


def get_url() -> str:
    url = os.getenv("DATABASE_URL", "postgresql+asyncpg://verirag:verirag_secret@localhost:5432/verirag")
    if not url.startswith("postgresql+asyncpg"):
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    return url


def run_migrations_offline() -> None:
    context.configure(
        url=get_url(), target_metadata=target_metadata,
        literal_binds=True, dialect_opts={"paramstyle": "named"},
        include_schemas=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata,
                      include_schemas=True, compare_server_default=True)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = create_async_engine(get_url())
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


# IMPORTANT: always guard with is_offline_mode() — never run at import time
if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
'@
wf "alembic\env.py" $f08

# ─────────────────────────────────────────────────────────────
# FIX 9 — frontend hooks: TanStack Query v5 refetchInterval API
# ─────────────────────────────────────────────────────────────
$f09 = @'
/**
 * hooks/useEvalRuns.js — React Query hooks for eval runs + regression data.
 * TanStack Query v5: refetchInterval receives { data, query } not data directly.
 */
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { listEvalRuns, getRegressions, startSampleEval, deleteEvalRun, getEvalStatus } from '../api/client.js'

export const EVAL_RUNS_KEY = ['eval-runs']
export const REGRESSIONS_KEY = ['regressions']

export function useEvalRuns({ limit = 50 } = {}) {
  return useQuery({
    queryKey: [...EVAL_RUNS_KEY, limit],
    queryFn: () => listEvalRuns({ limit }),
    // v5 API: refetchInterval receives { data } destructure, not raw data
    refetchInterval: ({ data } = {}) => {
      const hasRunning = data?.some((r) => r.status === 'running')
      return hasRunning ? 8_000 : 30_000
    },
  })
}

export function useRegressions() {
  return useQuery({
    queryKey: REGRESSIONS_KEY,
    queryFn: getRegressions,
    refetchInterval: 30_000,
  })
}

export function useEvalStatus() {
  return useQuery({
    queryKey: ['eval-status'],
    queryFn: getEvalStatus,
    refetchInterval: 10_000,
  })
}

export function useStartSampleEval() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (versionTag) => startSampleEval(versionTag),
    onSuccess: () => qc.invalidateQueries({ queryKey: EVAL_RUNS_KEY }),
  })
}

export function useDeleteEvalRun() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (runId) => deleteEvalRun(runId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: EVAL_RUNS_KEY })
      qc.invalidateQueries({ queryKey: REGRESSIONS_KEY })
    },
  })
}
'@
wf "frontend\src\hooks\useEvalRuns.js" $f09

$f09b = @'
/**
 * hooks/useEvalDetails.js — React Query hooks for a single eval run + its cases.
 * TanStack Query v5: refetchInterval receives { data } not data directly.
 */
import { useQuery } from '@tanstack/react-query'
import { getEvalRun, getEvalCases } from '../api/client.js'

export function useEvalRun(runId) {
  return useQuery({
    queryKey: ['eval-run', runId],
    queryFn: () => getEvalRun(runId),
    enabled: !!runId,
    // v5 API: destructure { data } from the query object
    refetchInterval: ({ data } = {}) => (data?.status === 'running' ? 5_000 : false),
  })
}

export function useEvalCases(runId, { page = 1, pageSize = 20 } = {}) {
  return useQuery({
    queryKey: ['eval-cases', runId, page, pageSize],
    queryFn: () => getEvalCases(runId, { page, pageSize }),
    enabled: !!runId,
    placeholderData: (prev) => prev,
  })
}
'@
wf "frontend\src\hooks\useEvalDetails.js" $f09b

# ─────────────────────────────────────────────────────────────
# FIX 10-16 — Missing frontend config + entry files
# ─────────────────────────────────────────────────────────────
$f10 = @'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      '/api': { target: 'http://localhost:8000', changeOrigin: true },
      '/health': { target: 'http://localhost:8000', changeOrigin: true },
    },
  },
})
'@
wf "frontend\vite.config.js" $f10

$f11 = @'
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#f0f4ff', 100: '#e0e9ff',
          500: '#4f6ef7', 600: '#3d5ce8', 700: '#2d4ad4',
        },
      },
      keyframes: {
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
      },
      animation: {
        shimmer: 'shimmer 1.5s infinite',
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
    },
  },
  plugins: [],
}
'@
wf "frontend\tailwind.config.js" $f11

$f12 = @'
export default { plugins: { tailwindcss: {}, autoprefixer: {} } }
'@
wf "frontend\postcss.config.js" $f12

$f13 = @'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>VeriRAG — RAG Evaluation Platform</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
'@
wf "frontend\index.html" $f13

$f14 = @'
import React from 'react'
import ReactDOM from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ReactQueryDevtools } from '@tanstack/react-query-devtools'
import App from './App.jsx'
import './index.css'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: 2,
      refetchOnWindowFocus: true,
    },
  },
})

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  </React.StrictMode>,
)
'@
wf "frontend\src\main.jsx" $f14

$f15 = @'
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  body { @apply bg-slate-950 text-slate-100 antialiased; }
  ::-webkit-scrollbar { @apply w-1.5; }
  ::-webkit-scrollbar-track { @apply bg-slate-900; }
  ::-webkit-scrollbar-thumb { @apply bg-slate-700 rounded-full; }
}

@layer utilities {
  .skeleton {
    @apply relative overflow-hidden bg-slate-800 rounded-lg;
  }
  .skeleton::after {
    content: '';
    @apply absolute inset-0;
    background: linear-gradient(90deg, transparent 0%, rgba(148,163,184,0.07) 50%, transparent 100%);
    background-size: 200% 100%;
    animation: shimmer 1.5s infinite;
  }
  .glass {
    @apply bg-slate-900/60 backdrop-blur-sm border border-slate-800;
  }
}
'@
wf "frontend\src\index.css" $f15

$f16 = @'
/**
 * PipelinePage — two-panel layout: document ingestion + RAG query interface.
 */
import { useState } from 'react'
import { startEvalRun } from '../api/client.js'
import { useStartSampleEval } from '../hooks/useEvalRuns.js'
import IngestPanel from '../components/pipeline/IngestPanel.jsx'
import QueryPanel from '../components/pipeline/QueryPanel.jsx'

export default function PipelinePage() {
  const [evalCase, setEvalCase] = useState(null)
  const [groundTruth, setGroundTruth] = useState('')
  const [versionTag, setVersionTag] = useState('v1.0.0-live')
  const [submitted, setSubmitted] = useState(false)
  const [submitError, setSubmitError] = useState('')
  const startSample = useStartSampleEval()

  const handleEvalCase = (c) => {
    setEvalCase(c)
    setSubmitted(false)
    setSubmitError('')
    setTimeout(() => document.getElementById('eval-form')?.scrollIntoView({ behavior: 'smooth' }), 100)
  }

  const handleSubmitEval = async () => {
    if (!evalCase || !groundTruth.trim()) return
    try {
      await startEvalRun({
        version_tag: versionTag,
        pipeline_name: 'live-query-eval',
        test_cases: [{ ...evalCase, ground_truth: groundTruth }],
        metadata: { source: 'pipeline_query_panel' },
      })
      setSubmitted(true)
      setEvalCase(null)
      setGroundTruth('')
    } catch (e) {
      setSubmitError(e.message)
    }
  }

  return (
    <div className="p-6 max-w-7xl space-y-6">
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <div>
          <h2 className="text-xs font-medium text-slate-500 uppercase tracking-wider mb-3">Document Ingestion</h2>
          <IngestPanel />
        </div>
        <div>
          <h2 className="text-xs font-medium text-slate-500 uppercase tracking-wider mb-3">Query Pipeline</h2>
          <QueryPanel onEvalCase={handleEvalCase} />
        </div>
      </div>

      {evalCase && (
        <div id="eval-form" className="glass rounded-xl p-5">
          <h3 className="text-sm font-semibold text-slate-200 mb-1">Evaluate this Query</h3>
          <p className="text-xs text-slate-500 mb-4">Add a ground truth and submit to create a 1-case eval run.</p>
          <div className="space-y-3">
            <div>
              <label className="text-xs text-slate-500 block mb-1">Question</label>
              <div className="bg-slate-800 rounded-lg px-3 py-2 text-xs text-slate-300 border border-slate-700">{evalCase.question}</div>
            </div>
            <div>
              <label className="text-xs text-slate-500 block mb-1">Ground Truth <span className="text-red-400">*</span></label>
              <textarea
                value={groundTruth}
                onChange={(e) => setGroundTruth(e.target.value)}
                placeholder="The ideal, complete answer to this question..."
                rows={3}
                className="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 focus:outline-none focus:border-brand-500 resize-none"
              />
            </div>
            <div className="flex items-center gap-3">
              <div className="flex-1">
                <label className="text-xs text-slate-500 block mb-1">Version Tag</label>
                <input
                  value={versionTag}
                  onChange={(e) => setVersionTag(e.target.value)}
                  className="w-full bg-slate-800 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-300 font-mono focus:outline-none focus:border-brand-500"
                />
              </div>
              <button
                onClick={handleSubmitEval}
                disabled={!groundTruth.trim()}
                className="mt-5 px-5 py-2 rounded-lg bg-brand-500 hover:bg-brand-600 text-white text-sm font-medium transition-colors disabled:opacity-50"
              >
                Submit Eval
              </button>
            </div>
            {submitError && <p className="text-xs text-red-400">{submitError}</p>}
          </div>
        </div>
      )}

      {submitted && (
        <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/5 px-4 py-3 text-xs">
          <p className="text-emerald-400 font-medium">Evaluation started</p>
          <p className="text-slate-400 mt-1">Check the <a href="/" className="text-brand-400 hover:underline">Dashboard</a> for results.</p>
        </div>
      )}

      <div className="glass rounded-xl p-5">
        <h3 className="text-sm font-semibold text-slate-200 mb-3">Quick Actions</h3>
        <div className="flex flex-wrap gap-3">
          <button
            onClick={() => startSample.mutate('v0.0.1-quick')}
            disabled={startSample.isPending}
            className="text-xs border border-slate-700 hover:border-slate-600 text-slate-300 px-4 py-2 rounded-lg transition-colors disabled:opacity-50"
          >
            {startSample.isPending ? 'Starting...' : 'Run Sample Evaluation (10 cases)'}
          </button>
          <a href="/docs" target="_blank" rel="noreferrer"
            className="text-xs border border-slate-700 hover:border-slate-600 text-slate-400 px-4 py-2 rounded-lg transition-colors">
            API Docs
          </a>
        </div>
      </div>
    </div>
  )
}
'@
wf "frontend\src\pages\PipelinePage.jsx" $f16

# ─────────────────────────────────────────────────────────────
# FIX 17 — Delete junk files
# ─────────────────────────────────────────────────────────────
Write-Host "`n  Cleaning up junk files..."
@("backend\models_v2.py", "fix_pipeline.py", "fix_pipeline_content.txt") | ForEach-Object {
    $p = Join-Path $BASE $_
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  DELETED $_" }
}

# ─────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────
Write-Host "`n=== ALL FIXES APPLIED ===" -ForegroundColor Green
Write-Host @"

NEXT STEPS:
-----------
1. Add your API keys to .env (copy from .env.example):
      GROQ_API_KEY=gsk_...
      DATABASE_URL=postgresql+asyncpg://verirag:verirag_secret@localhost:5432/verirag
      (LANGCHAIN_API_KEY is now optional)

2. Start PostgreSQL:
      docker-compose up -d postgres

3. Run migrations:
      alembic upgrade head

4. Start backend:
      uvicorn backend.main:app --reload --port 8000

5. Start frontend (separate terminal):
      cd frontend
      npm install
      npm run dev

Dashboard: http://localhost:3000
API docs:  http://localhost:8000/docs

FIXES APPLIED (22 issues):
  [1]  config.py        — langchain optional, regression_threshold, max_concurrent_evals
  [2]  models.py        — regression fields (has_regression, regression_details, etc.)
  [3]  rag/pipeline.py  — fixed method names, return keys, attr names, positional-arg bug
  [4]  schemas.py       — added MetricDelta, RegressionSummary, EvalRunWithRegression
  [5]  routers/eval.py  — semaphore, /regressions, /status endpoints
  [6]  ragas_runner.py  — LangchainLLMWrapper, get_running_loop(), regression detection
  [7]  langsmith.py     — guard empty API key
  [8]  alembic/env.py   — proper is_offline_mode() guard, no module-level asyncio.run
  [9]  useEvalRuns.js   — TanStack v5 refetchInterval({ data }) API
  [10] useEvalDetails.js— TanStack v5 refetchInterval({ data }) API
  [11] vite.config.js   — created (was missing)
  [12] tailwind.config  — created + animate-pulse-slow added
  [13] postcss.config   — created (was missing)
  [14] index.html       — created (was missing)
  [15] main.jsx         — created (was missing)
  [16] index.css        — created (was missing)
  [17] PipelinePage.jsx — created (was missing, fixed dynamic import bug)
  [18] models_v2.py     — deleted (duplicate)
  [19] fix_pipeline.py  — deleted (junk)
  [20] fix_pipeline_content.txt — deleted (junk)
"@
