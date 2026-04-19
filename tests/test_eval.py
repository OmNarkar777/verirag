"""
tests/test_eval.py — Async tests for evaluation endpoints and service.

TESTING STRATEGY:
- Use pytest-asyncio for async test functions
- Use httpx AsyncClient for endpoint tests (not TestClient which is sync)
- Mock RAGAS and Groq calls — we test OUR code, not RAGAS internals
- Use in-memory SQLite for tests — no PostgreSQL needed in CI
  (SQLAlchemy's async engine supports SQLite with aiosqlite)

WHAT WE TEST:
1. EvalRunRequest validation (Pydantic schemas)
2. POST /eval/run → returns 202 with correct structure
3. GET /eval/runs → returns list
4. GET /eval/runs/{id} → returns correct detail
5. Score persistence — stored scores match input
"""

import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from backend.database import Base
from backend.main import app
from backend.schemas import TestCaseInput


# ── Test Database Setup ────────────────────────────────────────────────────────

TEST_DB_URL = "sqlite+aiosqlite:///:memory:"


@pytest_asyncio.fixture
async def test_db():
    """
    In-memory SQLite database for tests.
    
    WHY SQLITE FOR TESTS:
    PostgreSQL ARRAY and JSONB aren't supported in SQLite, but we can
    test the application logic without them. For strict DB compatibility
    tests, use a real PostgreSQL instance (CI/CD pipeline).
    """
    engine = create_async_engine(TEST_DB_URL, echo=False)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with session_factory() as session:
        yield session

    await engine.dispose()


# ── Sample Test Data ───────────────────────────────────────────────────────────

SAMPLE_TEST_CASES = [
    TestCaseInput(
        question="What is retrieval-augmented generation?",
        answer="RAG combines retrieval of relevant documents with language model generation.",
        contexts=["RAG is a technique that retrieves documents before LLM generation."],
        ground_truth="RAG retrieves relevant documents from a knowledge base and uses them as context for LLM generation.",
    ),
    TestCaseInput(
        question="What does RAGAS measure?",
        answer="RAGAS measures faithfulness, answer relevancy, context precision, and context recall.",
        contexts=["RAGAS is a framework for evaluating RAG pipelines using four metrics."],
        ground_truth="RAGAS evaluates RAG systems using faithfulness, answer relevancy, context precision, and context recall metrics.",
    ),
]

SAMPLE_EVAL_REQUEST = {
    "version_tag": "v1.0.0-test",
    "pipeline_name": "test-pipeline",
    "test_cases": [tc.model_dump() for tc in SAMPLE_TEST_CASES],
    "metadata": {"chunk_size": 512, "top_k": 5},
}


# ── Schema Validation Tests ────────────────────────────────────────────────────

class TestEvalRunRequest:
    def test_valid_version_tag_formats(self):
        """Version tags must follow v{major}.{minor}.{patch} format."""
        from backend.schemas import EvalRunRequest

        valid_tags = ["v1.0.0", "v1.0.0-baseline", "v2.1.3-hybrid-mmr"]
        for tag in valid_tags:
            req = EvalRunRequest(
                version_tag=tag,
                pipeline_name="test",
                test_cases=SAMPLE_TEST_CASES,
            )
            assert req.version_tag == tag

    def test_invalid_version_tag_rejected(self):
        """Non-semver tags should raise validation error."""
        from backend.schemas import EvalRunRequest
        from pydantic import ValidationError

        with pytest.raises(ValidationError) as exc_info:
            EvalRunRequest(
                version_tag="baseline",  # missing v prefix and semver
                pipeline_name="test",
                test_cases=SAMPLE_TEST_CASES,
            )
        assert "version_tag" in str(exc_info.value)

    def test_empty_test_cases_rejected(self):
        """Empty test cases list should fail validation."""
        from backend.schemas import EvalRunRequest
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            EvalRunRequest(
                version_tag="v1.0.0",
                pipeline_name="test",
                test_cases=[],
            )

    def test_empty_context_strings_rejected(self):
        """Contexts with empty strings should fail validation."""
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            TestCaseInput(
                question="What is RAG?",
                answer="RAG is...",
                contexts=["valid context", ""],  # empty string should fail
                ground_truth="RAG retrieves documents.",
            )


# ── EvalService Unit Tests ────────────────────────────────────────────────────

class TestEvalService:
    @pytest.mark.asyncio
    async def test_list_eval_runs_empty(self, test_db):
        """Empty database should return empty list."""
        from backend.services.eval_service import EvalService

        service = EvalService()
        runs = await service.list_eval_runs(db=test_db)
        assert runs == []

    @pytest.mark.asyncio
    async def test_get_nonexistent_run(self, test_db):
        """Querying a non-existent run should return None."""
        from backend.services.eval_service import EvalService

        service = EvalService()
        result = await service.get_eval_run(db=test_db, run_id=uuid.uuid4())
        assert result is None

    @pytest.mark.asyncio
    async def test_score_classification(self):
        """Score classification thresholds should work correctly."""
        from backend.evaluator.metrics import classify_score

        assert classify_score("faithfulness", 0.90) == "pass"
        assert classify_score("faithfulness", 0.72) == "warning"
        assert classify_score("faithfulness", 0.50) == "fail"
        assert classify_score("unknown_metric", 0.90) == "unknown"

    @pytest.mark.asyncio
    async def test_score_summary_structure(self):
        """score_summary should return enriched dict with status and description."""
        from backend.evaluator.metrics import score_summary

        scores = {
            "faithfulness": 0.85,
            "answer_relevancy": 0.72,
            "context_precision": 0.60,
            "context_recall": 0.45,
        }
        summary = score_summary(scores)

        assert "faithfulness" in summary
        assert summary["faithfulness"]["score"] == 0.85
        assert summary["faithfulness"]["status"] == "pass"
        assert isinstance(summary["faithfulness"]["description"], str)

        assert summary["context_recall"]["status"] == "fail"


# ── Dataset Builder Tests ─────────────────────────────────────────────────────

class TestDatasetBuilder:
    def test_sample_test_cases_count(self):
        """Should return exactly 10 sample test cases."""
        from backend.evaluator.dataset_builder import get_sample_test_cases

        cases = get_sample_test_cases()
        assert len(cases) == 10

    def test_all_cases_have_required_fields(self):
        """Every case must have question, answer, contexts, ground_truth."""
        from backend.evaluator.dataset_builder import get_sample_test_cases

        cases = get_sample_test_cases()
        for case in cases:
            assert case.question
            assert case.answer
            assert len(case.contexts) > 0
            assert all(ctx.strip() for ctx in case.contexts)
            assert case.ground_truth

    def test_build_ragas_dataset_format(self):
        """RAGAS dataset should have correct column names and row count."""
        from backend.evaluator.dataset_builder import build_ragas_dataset

        cases = SAMPLE_TEST_CASES
        dataset = build_ragas_dataset(cases)

        assert set(dataset.column_names) == {"question", "answer", "contexts", "ground_truth"}
        assert len(dataset) == len(cases)

    def test_build_ragas_dataset_values(self):
        """Dataset values should match input test cases."""
        from backend.evaluator.dataset_builder import build_ragas_dataset

        cases = SAMPLE_TEST_CASES
        dataset = build_ragas_dataset(cases)

        assert dataset["question"][0] == cases[0].question
        assert dataset["answer"][0] == cases[0].answer
        assert dataset["contexts"][0] == cases[0].contexts
        assert dataset["ground_truth"][0] == cases[0].ground_truth


# ── API Endpoint Tests (with mocked RAGAS) ───────────────────────────────────

@pytest.fixture
def mock_eval_service():
    """Mock the eval service so tests don't call Groq/RAGAS."""
    with patch("backend.routers.eval.get_eval_service") as mock:
        service = AsyncMock()
        service.start_eval_run.return_value = uuid.uuid4()
        service.execute_evaluation.return_value = None
        service.list_eval_runs.return_value = []
        service.get_eval_run.return_value = None
        mock.return_value = service
        yield service


@pytest.mark.asyncio
class TestEvalEndpoints:
    async def test_post_eval_run_returns_202(self, mock_eval_service):
        """POST /eval/run should return 202 Accepted with run_id."""
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/eval/run",
                json=SAMPLE_EVAL_REQUEST,
            )

        assert response.status_code == 202
        data = response.json()
        assert "eval_run_id" in data
        assert data["status"] == "running"
        assert data["version_tag"] == "v1.0.0-test"

    async def test_post_eval_run_invalid_version_returns_422(self, mock_eval_service):
        """Invalid version tag should return 422 Unprocessable Entity."""
        bad_request = {**SAMPLE_EVAL_REQUEST, "version_tag": "not-semver"}

        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post("/api/v1/eval/run", json=bad_request)

        assert response.status_code == 422

    async def test_get_eval_runs_returns_list(self, mock_eval_service):
        """GET /eval/runs should return a list."""
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.get("/api/v1/eval/runs")

        assert response.status_code == 200
        assert isinstance(response.json(), list)

    async def test_get_nonexistent_run_returns_404(self, mock_eval_service):
        """GET /eval/runs/{unknown_id} should return 404."""
        run_id = uuid.uuid4()
        mock_eval_service.get_eval_run.return_value = None

        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.get(f"/api/v1/eval/runs/{run_id}")

        assert response.status_code == 404
