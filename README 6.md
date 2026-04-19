# VeriRAG — Production RAG Evaluation & Observability Platform

> Evaluate, version, and debug your RAG pipeline quality with RAGAS scores stored in PostgreSQL — with automatic regression detection when your pipeline changes.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         VeriRAG System                               │
│                                                                      │
│  ┌─────────────────────────┐    ┌─────────────────────────────────┐  │
│  │   React Frontend        │    │   FastAPI Backend               │  │
│  │   (Vite + Tailwind)     │◄──►│   (async, Python 3.11)         │  │
│  │                         │    │                                 │  │
│  │  Dashboard              │    │  POST /eval/run ──► EvalService │  │
│  │  ├─ MetricCards         │    │       │              │          │  │
│  │  ├─ TrendChart          │    │   BackgroundTask  RagasRunner   │  │
│  │  ├─ RegressionAlert  ◄──┼────┼───── has_regression ◄──────────┤  │
│  │  └─ RunsTable           │    │                    │            │  │
│  │                         │    │  POST /pipeline/query           │  │
│  │  RunDetails             │    │       │                         │  │
│  │  ├─ MetricCards         │    │  RAGPipeline                    │  │
│  │  ├─ ScoreDistribution   │    │  ├─ VectorStoreManager (MMR)   │  │
│  │  └─ CaseTable (paged)   │    │  └─ Groq LLM (Llama 3.3 70B)  │  │
│  │                         │    │                                 │  │
│  │  Pipeline               │    │  RegressionService              │  │
│  │  ├─ IngestPanel         │    │  └─ detect_and_store() ◄───────┤  │
│  │  └─ QueryPanel          │    │                                 │  │
│  └─────────────────────────┘    └──────────┬──────────────────────┘  │
│                                            │                         │
│              ┌─────────────────────────────┼─────────────────┐       │
│              │                             │                 │       │
│         PostgreSQL 15                 ChromaDB          LangSmith    │
│         ├─ eval_runs                  (vectors +        (traces +    │
│         │  ├─ version_tag             MMR search)       evals)       │
│         │  ├─ avg_* scores                                           │
│         │  ├─ has_regression                                         │
│         │  └─ regression_details                                     │
│         └─ eval_cases                                                │
│            └─ per-question scores                                    │
└──────────────────────────────────────────────────────────────────────┘
```

---

## RAGAS Metrics — What They Actually Measure

### Faithfulness (0–1)
**Does the answer contain ONLY information from the retrieved context?**

RAGAS decomposes the answer into atomic claims, then asks the LLM: "Is this claim supported by the provided context?" Score = `supported_claims / total_claims`. A score of 0.85 means 85% of the answer's claims were grounded in retrieved chunks — the other 15% were hallucinated from parametric knowledge. **Fix low faithfulness**: strengthen the system prompt to restrict the model to provided context only, or improve retrieval coverage so the answer doesn't need to fill gaps.

### Answer Relevancy (0–1)
**Does the answer actually address the question that was asked?**

RAGAS generates N reverse questions from the answer, then measures cosine similarity between the original question and those reverse questions. A technically correct but off-topic answer scores low here. **Fix low relevancy**: improve retrieval to surface more directly relevant chunks. If the top-k chunks are about adjacent topics, the LLM's answer will drift from the question.

### Context Precision (0–1)
**Are the useful retrieved chunks ranked highest?**

For each retrieved chunk, RAGAS judges whether it contributed to generating a correct answer. Then measures ranking quality — useful chunks should appear at rank 1, 2, 3, not buried at rank 8, 9, 10. A score of 0.60 means relevant chunks are mixed randomly with irrelevant ones. **Fix low precision**: implement MMR retrieval (already in this codebase), a reranker model (cross-encoder), or a better embedding model.

### Context Recall (0–1)
**Does the retrieved context cover everything in the ground truth?**

RAGAS decomposes the ground truth answer into sentences, then asks: "Could this sentence be inferred from the retrieved context?" Score = `covered_sentences / total_sentences`. **Fix low recall**: increase `top_k`, reduce chunk size (denser chunks = better coverage), or add BM25 hybrid search to catch exact-match terms that semantic search misses.

---

## The Key Feature: Regression Detection

After each eval run completes, VeriRAG automatically compares its scores against the most recent previous completed run. If any metric drops more than the configured threshold (default: **10 absolute points**), the run is flagged:

```
has_regression = true
regression_details = {
  "faithfulness": {
    "previous": 0.87,
    "current": 0.71,
    "delta": -0.16,
    "threshold": 0.10,
    "is_regression": true
  }
}
```

The dashboard shows a prominent red banner: **"Regression detected: faithfulness 87% → 71% in v1.2.0-new-chunker"**

This is what separates a production eval system from a one-off script — you know immediately when a pipeline change made quality worse.

---

## Quick Start

### Prerequisites
- Docker + Docker Compose
- Node.js 20+
- Groq API key ([console.groq.com](https://console.groq.com) — free tier)
- LangSmith API key ([smith.langchain.com](https://smith.langchain.com) — free tier)

### 1. Configure environment

```bash
git clone https://github.com/yourusername/verirag && cd verirag
cp .env.example .env
# Edit .env — add GROQ_API_KEY and LANGCHAIN_API_KEY
```

### 2. Start infrastructure

```bash
docker-compose up -d postgres pgadmin
# Wait ~10 seconds for PostgreSQL to initialize
```

### 3. Run database migrations

```bash
pip install -r requirements.txt
alembic upgrade head
# Applies 001_initial_schema + 002_add_regression_fields
```

### 4. Start the API

```bash
uvicorn backend.main:app --reload --port 8000
# FastAPI docs: http://localhost:8000/docs
# Health check: http://localhost:8000/health
```

### 5. Start the frontend

```bash
cd frontend
npm install
npm run dev
# Dashboard: http://localhost:3000
```

### 6. Ingest documents

```bash
curl -X POST http://localhost:8000/api/v1/pipeline/ingest/text \
  -F "text=Retrieval-Augmented Generation combines document retrieval with LLM generation. The pipeline retrieves relevant chunks from a vector store and provides them as context to the language model, reducing hallucination." \
  -F "filename=rag-intro.txt"
```

### 7. Run the sample evaluation

```bash
curl -X POST "http://localhost:8000/api/v1/eval/run/sample?version_tag=v1.0.0-baseline"
# Returns {"eval_run_id": "...", "status": "running"}
# Takes 5-10 minutes (RAGAS makes ~150 Groq API calls)
```

### 8. Poll for results

```bash
curl http://localhost:8000/api/v1/eval/runs/{eval_run_id}
# status: "running" → "completed"
# Then check: http://localhost:3000 for the dashboard
```

### 9. Trigger regression detection

Run a second evaluation with a slightly different config to see regression detection in action:

```bash
curl -X POST "http://localhost:8000/api/v1/eval/run/sample?version_tag=v1.1.0-different-config"
# After completion, check GET /api/v1/eval/regressions
```

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | System health — DB + ChromaDB status |
| POST | `/api/v1/eval/run` | Start eval (202 Accepted + background task) |
| POST | `/api/v1/eval/run/sample` | Run built-in 10-case AI/ML sample |
| GET | `/api/v1/eval/runs` | List all runs with regression flags |
| GET | `/api/v1/eval/runs/{id}` | Full run detail + all case scores |
| GET | `/api/v1/eval/runs/{id}/cases` | Paginated per-case scores (CSV export in UI) |
| GET | `/api/v1/eval/regressions` | **All runs with detected regressions** |
| GET | `/api/v1/eval/status` | Concurrent eval count + rate limit info |
| DELETE | `/api/v1/eval/runs/{id}` | Delete run + cascaded cases |
| POST | `/api/v1/pipeline/ingest` | Upload PDF or text file |
| POST | `/api/v1/pipeline/ingest/text` | Ingest raw text |
| POST | `/api/v1/pipeline/query` | Query RAG pipeline → answer + chunks |
| GET | `/api/v1/pipeline/stats` | ChromaDB collection stats |
| GET | `/api/v1/pipeline/documents` | Audit list of ingested documents |

Full interactive docs: `http://localhost:8000/docs`

---

## Project Structure

```
verirag/
├── backend/
│   ├── main.py                     # FastAPI app, lifespan startup, middleware
│   ├── config.py                   # Pydantic-settings (type-safe .env parsing)
│   ├── database.py                 # Async SQLAlchemy engine + session factory
│   ├── models.py                   # ORM models with regression + LangSmith fields
│   ├── schemas.py                  # Pydantic v2 request/response schemas
│   ├── rag/
│   │   ├── pipeline.py             # End-to-end RAG: retrieve → generate
│   │   ├── vectorstore.py          # ChromaDB + MMR implementation (from scratch)
│   │   └── retriever.py            # Retrieval strategy layer (LangSmith traced)
│   ├── evaluator/
│   │   ├── ragas_runner.py         # RAGAS engine: eval → persist → regress → tag
│   │   ├── metrics.py              # Metric definitions, thresholds, explanations
│   │   └── dataset_builder.py      # RAGAS Dataset builder + 10 sample QA pairs
│   ├── routers/
│   │   ├── eval.py                 # Eval endpoints + semaphore rate limiting
│   │   ├── pipeline.py             # Ingest + query endpoints
│   │   └── health.py               # Health check (DB + ChromaDB connectivity)
│   └── services/
│       ├── eval_service.py         # Business logic: create/list/query eval runs
│       ├── regression_service.py   # ★ Regression detection engine
│       └── langsmith_service.py    # LangSmith trace utilities + tagging
│
├── frontend/
│   └── src/
│       ├── api/client.js           # Axios instance + all API functions
│       ├── hooks/                  # React Query hooks (polling, mutations)
│       ├── utils/scoreColor.js     # Threshold-based color system
│       ├── components/
│       │   ├── layout/             # Sidebar + Header
│       │   ├── dashboard/          # MetricCard, TrendChart, RunsTable, RegressionAlert
│       │   ├── eval/               # RunDetails, CaseTable (paginated), ScoreDistribution
│       │   └── pipeline/           # IngestPanel (drag-drop), QueryPanel
│       └── pages/                  # DashboardPage, RunDetailsPage, PipelinePage
│
├── alembic/
│   └── versions/
│       ├── 001_initial_schema.py   # eval_runs, eval_cases, pipeline_documents
│       └── 002_add_regression_fields.py  # has_regression, regression_details, langsmith_url
│
├── tests/
│   ├── test_eval.py                # Async tests for eval service + endpoints
│   └── test_pipeline.py           # VectorStore, retriever, pipeline endpoint tests
│
├── docker-compose.yml              # PostgreSQL 15 + pgAdmin + app
├── Dockerfile
├── requirements.txt                # Pinned Python deps
└── .env.example                    # All required environment variables
```

---

## Production Patterns

### Regression Detection (the differentiator)
After each completed eval, `regression_service.py` compares all 4 metric scores against the most recent prior run. Results are stored as JSONB on the `EvalRun` record with a Boolean `has_regression` index for O(1) dashboard queries. The UI shows a prominent banner with before/after values per metric.

### Async Everything
All DB operations use asyncpg. RAGAS (synchronous) runs in a thread pool via `asyncio.run_in_executor` — never blocks the FastAPI event loop during 5-minute eval runs.

### Concurrency Control
An `asyncio.Semaphore(5)` caps concurrent RAGAS runs. Each run makes ~200 Groq API calls; >5 simultaneous runs cause cascading rate limit failures. The semaphore is acquired inside the BackgroundTask — the API always returns 202 instantly.

### Version Tracking
Every eval run has a semantic version tag (`v1.0.0-baseline`, `v1.1.0-mmr`, `v2.0.0-reranker`). This enables SQL queries like:
```sql
SELECT version_tag, avg_faithfulness, avg_context_recall
FROM eval_runs WHERE status = 'completed'
ORDER BY created_at DESC;
```

### Schema Evolution
Two Alembic migrations track all schema changes. `alembic upgrade head` is idempotent and runs automatically in the Docker entrypoint.

---

## Extending VeriRAG

### Add a re-ranker (cross-encoder)
```python
# In rag/retriever.py, after MMR retrieval:
from sentence_transformers import CrossEncoder
reranker = CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2')
scores = reranker.predict([(query, c['content']) for c in chunks])
chunks = [c for _, c in sorted(zip(scores, chunks), reverse=True)]
```
Tag the new version `v2.0.0-reranker` and run eval. The regression detector will flag any metric that drops.

### Add hybrid BM25 + semantic search
1. Add `rank_bm25` to requirements.txt
2. Build a BM25 index over ingested chunks
3. Merge BM25 + semantic scores with Reciprocal Rank Fusion in `retriever.py`
4. Version tag: `v2.0.0-hybrid-bm25`

### Add a new RAGAS metric
1. Import from `ragas.metrics` in `evaluator/metrics.py`
2. Add the column to `EvalCase` model + generate a new Alembic migration
3. Update `_persist_cases()` in `ragas_runner.py`
4. Add the field to `EvalCaseResult` schema + CaseTable columns

---

## Dashboard Screenshots

*After running 2+ evaluations, the dashboard displays:*

**Main Dashboard (`/`)**
- 4 metric cards with percentage scores and ↑↓ delta from previous run
- Line chart showing all 4 metrics across the last 10 runs
- Red regression alert banner if any metric dropped >10%
- Table of all runs with version tags, scores, and status badges

**Run Detail (`/runs/:id`)**
- Aggregate score cards for the specific run
- 4 score distribution histograms (binned 0–20%, 20–40%, etc.)
- Paginated per-case table with color-coded scores (green/amber/red)
- Export to CSV button
- LangSmith trace link

**Pipeline (`/pipeline`)**
- Drag-and-drop file upload → chunk count displayed on success
- Query box with retrieved chunks shown below answer
- "Use as Eval Case" button to immediately evaluate a live query
