"""
Tests for src/rag/retriever.py using sample_cards as fixtures.
No Ollama / GPU required — uses deterministic fake embeddings.
"""
import hashlib
from pathlib import Path
from random import Random
from typing import List

import frontmatter
import pytest
from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings

from src.rag.retriever import build_hybrid_retriever

SAMPLE_DIR = Path(__file__).parents[1] / "data" / "sample_cards"


class _FakeEmbeddings(Embeddings):
    """Deterministic fake embeddings (no model download needed)."""

    def embed_documents(self, texts: List[str]) -> List[List[float]]:
        return [self._vec(t) for t in texts]

    def embed_query(self, text: str) -> List[float]:
        return self._vec(text)

    def _vec(self, text: str) -> List[float]:
        h = int(hashlib.md5(text.encode()).hexdigest(), 16)
        rng = Random(h)
        vec = [rng.gauss(0, 1) for _ in range(16)]
        norm = (sum(x ** 2 for x in vec) ** 0.5) or 1.0
        return [x / norm for x in vec]


def _load_sample_docs() -> List[Document]:
    docs = []
    for md_file in SAMPLE_DIR.rglob("*.md"):
        post = frontmatter.load(str(md_file))
        meta = dict(post.metadata)
        meta["source"] = str(md_file)
        docs.append(Document(page_content=post.content, metadata=meta))
    return docs


@pytest.fixture(scope="module")
def vs(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("chroma")
    docs = _load_sample_docs()
    assert docs, f"No sample cards found in {SAMPLE_DIR}"
    return Chroma.from_documents(docs, _FakeEmbeddings(), persist_directory=str(tmp))


# ── role visibility ────────────────────────────────────────────────────────────

def test_product_visible_to_warehouse(vs):
    retriever = build_hybrid_retriever(vs, role="warehouse", top_k=3)
    results = retriever.invoke("IC-8800 的定價")
    assert any("IC-8800" in d.page_content for d in results), \
        "warehouse should be able to retrieve IC-8800 product card"


def test_customer_invisible_to_warehouse(vs):
    """Warehouse must not receive customer cards — BM25 corpus is role-filtered."""
    retriever = build_hybrid_retriever(vs, role="warehouse", top_k=5)
    results = retriever.invoke("台灣科技股份有限公司 聯絡人 王大明")
    assert not any(
        d.metadata.get("entity_type") == "customer" for d in results
    ), "warehouse should never receive customer cards"


def test_customer_visible_to_sales(vs):
    retriever = build_hybrid_retriever(vs, role="sales", top_k=3)
    results = retriever.invoke("台灣科技股份有限公司")
    assert any(
        d.metadata.get("entity_type") == "customer" for d in results
    ), "sales should be able to retrieve customer cards"


def test_customer_visible_to_admin(vs):
    retriever = build_hybrid_retriever(vs, role="admin", top_k=3)
    results = retriever.invoke("台灣科技股份有限公司")
    assert any(
        d.metadata.get("entity_type") == "customer" for d in results
    )


# ── BM25 keyword hit ───────────────────────────────────────────────────────────

def test_bm25_keyword_hit_sku(vs):
    """BM25 should surface NJ-1001 when queried by exact SKU."""
    retriever = build_hybrid_retriever(vs, role="admin", top_k=3)
    results = retriever.invoke("NJ-1001 最低庫存水位")
    assert any("NJ-1001" in d.page_content for d in results)


# ── empty corpus ───────────────────────────────────────────────────────────────

def test_empty_for_unknown_role(vs):
    retriever = build_hybrid_retriever(vs, role="role_that_does_not_exist", top_k=3)
    results = retriever.invoke("anything")
    assert results == [], "unknown role should receive empty result list"
