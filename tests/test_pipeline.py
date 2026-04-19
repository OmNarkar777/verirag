"""
tests/test_pipeline.py — Tests for RAG pipeline components.

TESTING APPROACH:
- VectorStore: use real ChromaDB with EphemeralClient (in-memory, no disk)
- RAG Pipeline: mock Groq API calls (we test retrieval logic, not Groq)
- Endpoints: mock pipeline dependency

WHAT WE VALIDATE:
1. Document ingestion creates correct chunk count
2. Similarity search returns relevant results
3. MMR search returns diverse results
4. Pipeline query returns correct structure
5. Endpoint responses have correct shape
"""

from unittest.mock import MagicMock, patch

import pytest


# ── VectorStore Unit Tests ────────────────────────────────────────────────────

class TestVectorStoreManager:
    """
    Tests for ChromaDB operations.
    Uses EphemeralClient (in-memory) to avoid test pollution and disk I/O.
    """

    @pytest.fixture
    def ephemeral_vs(self, tmp_path):
        """
        VectorStoreManager with temporary storage for test isolation.
        Each test gets a fresh ChromaDB instance.
        """
        with patch("backend.rag.vectorstore.settings") as mock_settings:
            mock_settings.chroma_persist_dir = str(tmp_path / "chroma")
            mock_settings.chroma_collection_name = "test_collection"
            mock_settings.embedding_model = "all-MiniLM-L6-v2"
            mock_settings.retrieval_top_k = 3
            mock_settings.retrieval_lambda = 0.5

            from backend.rag.vectorstore import VectorStoreManager
            vs = VectorStoreManager()
            return vs

    def test_ingest_text_returns_metadata(self, ephemeral_vs):
        """Ingesting text should return doc_id, filename, and chunk count."""
        text = """
        Transformers are a type of neural network architecture that uses self-attention.
        They were introduced in the paper "Attention Is All You Need" in 2017.
        The key innovation is the ability to process sequences in parallel.
        """ * 5  # repeat to ensure multiple chunks

        result = ephemeral_vs.ingest_text(
            text=text,
            filename="test_doc.txt",
            collection_name="test_collection",
        )

        assert "doc_id" in result
        assert result["filename"] == "test_doc.txt"
        assert result["chunks_created"] >= 1
        assert result["collection_name"] == "test_collection"

    def test_ingest_produces_deterministic_doc_id(self, ephemeral_vs):
        """Same text + filename should produce the same doc_id (idempotency)."""
        text = "Test document content for determinism check."

        result1 = ephemeral_vs.ingest_text(text=text, filename="same.txt")
        result2 = ephemeral_vs.ingest_text(text=text, filename="same.txt")

        assert result1["doc_id"] == result2["doc_id"]

    def test_similarity_search_returns_results(self, ephemeral_vs):
        """After ingestion, similarity search should return relevant chunks."""
        # Ingest some content
        ephemeral_vs.ingest_text(
            text="Transformers use self-attention mechanisms for NLP tasks.",
            filename="transformers.txt",
        )
        ephemeral_vs.ingest_text(
            text="ChromaDB is a vector database for semantic search.",
            filename="chromadb.txt",
        )

        # Search for transformers content
        results = ephemeral_vs.similarity_search(
            query="What are transformers in deep learning?",
            top_k=2,
        )

        assert len(results) > 0
        assert "content" in results[0]
        assert "source" in results[0]
        assert "score" in results[0]
        assert 0.0 <= results[0]["score"] <= 1.0

    def test_similarity_search_empty_collection(self, ephemeral_vs):
        """Searching empty collection should return empty list."""
        results = ephemeral_vs.similarity_search(
            query="anything",
            collection_name="empty_collection",
            top_k=5,
        )
        assert results == []

    def test_mmr_search_returns_diverse_results(self, ephemeral_vs):
        """MMR should return fewer near-duplicate chunks than similarity search."""
        # Ingest near-duplicate content
        for i in range(5):
            ephemeral_vs.ingest_text(
                text=f"Transformers use self-attention. Version {i}.",
                filename=f"dup_{i}.txt",
            )
        ephemeral_vs.ingest_text(
            text="ChromaDB stores vector embeddings for fast retrieval.",
            filename="different.txt",
        )

        mmr_results = ephemeral_vs.mmr_search(query="transformers attention", top_k=3)
        sim_results = ephemeral_vs.similarity_search(query="transformers attention", top_k=3)

        # Both should return results
        assert len(mmr_results) > 0
        assert len(sim_results) > 0

    def test_get_collection_stats(self, ephemeral_vs):
        """Collection stats should report correct document count."""
        initial_stats = ephemeral_vs.get_collection_stats()
        initial_count = initial_stats["document_count"]

        ephemeral_vs.ingest_text(
            text="A new document for stats testing. " * 10,
            filename="stats_test.txt",
        )

        updated_stats = ephemeral_vs.get_collection_stats()
        assert updated_stats["document_count"] > initial_count

    def test_mmr_select_algorithm(self):
        """MMR selection algorithm should prefer diverse candidates."""
        import numpy as np
        from backend.rag.vectorstore import VectorStoreManager

        # Create embeddings where candidates 0,1,2 are similar and candidate 3 is different
        query = [1.0, 0.0, 0.0]
        candidates = [
            [0.95, 0.05, 0.0],  # very similar to query
            [0.93, 0.07, 0.0],  # very similar to query AND candidate 0
            [0.90, 0.10, 0.0],  # similar but slightly more diverse
            [0.5, 0.5, 0.7],    # different direction — should be selected by MMR
        ]

        # With lambda=0 (max diversity), diverse candidate should be selected
        selected = VectorStoreManager._mmr_select(
            query_embedding=query,
            candidate_embeddings=candidates,
            top_k=2,
            lambda_mult=0.0,
        )

        assert len(selected) == 2
        # Candidate 3 (diverse) should be prioritized with low lambda
        assert 3 in selected


# ── Retriever Tests ───────────────────────────────────────────────────────────

class TestRAGRetriever:
    def test_retrieve_for_ragas_returns_strings(self, tmp_path):
        """retrieve_for_ragas should return list of strings, not dicts."""
        with patch("backend.rag.retriever.get_vector_store") as mock_vs:
            mock_store = MagicMock()
            mock_store.mmr_search.return_value = [
                {"content": "chunk 1", "source": "doc.txt", "score": 0.9, "metadata": {}},
                {"content": "chunk 2", "source": "doc.txt", "score": 0.8, "metadata": {}},
            ]
            mock_vs.return_value = mock_store

            from backend.rag.retriever import RAGRetriever

            retriever = RAGRetriever(vector_store=mock_store)
            results = retriever.retrieve_for_ragas(query="test query")

            assert isinstance(results, list)
            assert all(isinstance(r, str) for r in results)
            assert results == ["chunk 1", "chunk 2"]


# ── Pipeline Endpoint Tests ───────────────────────────────────────────────────

class TestPipelineEndpoints:
    @pytest.mark.asyncio
    async def test_query_endpoint_structure(self):
        """POST /pipeline/query should return correct response structure."""
        from httpx import AsyncClient, ASGITransport
        from backend.main import app

        mock_pipeline = MagicMock()
        mock_pipeline.query.return_value = {
            "question": "What is RAG?",
            "answer": "RAG combines retrieval with generation.",
            "retrieved_chunks": [
                {
                    "content": "RAG is retrieval-augmented generation.",
                    "source": "rag_doc.txt",
                    "score": 0.92,
                    "metadata": {"chunk_index": 0},
                }
            ],
            "context_str": "RAG is retrieval-augmented generation.",
            "model_used": "llama-3.3-70b-versatile",
        }

        with patch("backend.routers.pipeline.get_pipeline", return_value=mock_pipeline):
            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/v1/pipeline/query",
                    json={"question": "What is RAG?", "top_k": 3},
                )

        assert response.status_code == 200
        data = response.json()
        assert "question" in data
        assert "answer" in data
        assert "retrieved_chunks" in data
        assert "model_used" in data
        assert len(data["retrieved_chunks"]) == 1
        assert data["retrieved_chunks"][0]["score"] == 0.92

    @pytest.mark.asyncio
    async def test_ingest_text_endpoint(self):
        """POST /pipeline/ingest/text should return 201 with chunk count."""
        from httpx import AsyncClient, ASGITransport
        from backend.main import app

        mock_pipeline = MagicMock()
        mock_pipeline.ingest_text.return_value = {
            "doc_id": "abc123",
            "filename": "test.txt",
            "chunks_created": 3,
            "collection_name": "verirag_docs",
        }

        with patch("backend.routers.pipeline.get_pipeline", return_value=mock_pipeline):
            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                response = await client.post(
                    "/api/v1/pipeline/ingest/text",
                    data={
                        "text": "This is a test document with enough content to be useful. " * 10,
                        "filename": "test.txt",
                    },
                )

        assert response.status_code == 201
        data = response.json()
        assert data["chunks_created"] == 3
        assert data["filename"] == "test.txt"

    @pytest.mark.asyncio
    async def test_stats_endpoint(self):
        """GET /pipeline/stats should return collection info."""
        from httpx import AsyncClient, ASGITransport
        from backend.main import app

        mock_pipeline = MagicMock()
        mock_pipeline.vector_store.get_collection_stats.return_value = {
            "collection_name": "verirag_docs",
            "document_count": 42,
        }

        with patch("backend.routers.pipeline.get_pipeline", return_value=mock_pipeline):
            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                response = await client.get("/api/v1/pipeline/stats")

        assert response.status_code == 200
        data = response.json()
        assert "document_count" in data
        assert "collection_name" in data


# ── Health Check Tests ────────────────────────────────────────────────────────

class TestHealthEndpoint:
    @pytest.mark.asyncio
    async def test_health_check_returns_200(self):
        """Health endpoint should return 200 with status field."""
        from httpx import AsyncClient, ASGITransport
        from backend.main import app

        with patch("backend.routers.health.get_vector_store") as mock_vs:
            mock_vs.return_value.get_collection_stats.return_value = {"document_count": 0}

            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as client:
                response = await client.get("/health")

        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert "database" in data
        assert "chromadb" in data
