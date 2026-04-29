import os
from typing import List, Union

from langchain_chroma import Chroma
from langchain_community.retrievers import BM25Retriever
from langchain_core.callbacks.manager import CallbackManagerForRetrieverRun
from langchain_core.documents import Document
from langchain_core.retrievers import BaseRetriever


class _EmptyRetriever(BaseRetriever):
    """No-op retriever returned when the role has no visible corpus."""

    def _get_relevant_documents(
        self, query: str, *, run_manager: CallbackManagerForRetrieverRun
    ) -> List[Document]:
        return []


def _rrf_merge(
    ranked_lists: List[List[Document]],
    weights: List[float],
    top_k: int,
    rrf_k: int = 60,
) -> List[Document]:
    """Reciprocal Rank Fusion with per-list weights."""
    seen: dict = {}
    for results, weight in zip(ranked_lists, weights):
        for rank, doc in enumerate(results):
            key = doc.page_content
            if key not in seen:
                seen[key] = {"doc": doc, "score": 0.0}
            seen[key]["score"] += weight / (rrf_k + rank + 1)
    sorted_items = sorted(seen.values(), key=lambda x: x["score"], reverse=True)
    return [item["doc"] for item in sorted_items[:top_k]]


class HybridRetriever(BaseRetriever):
    """BM25 (0.3) + ChromaDB vector (0.7) retriever scoped to a single role.

    BM25 corpus is pre-filtered to role-visible documents so warehouse cannot
    receive customer documents even through lexical matching.
    """

    bm25: BM25Retriever
    chroma: BaseRetriever
    top_k: int
    bm25_weight: float = 0.3
    chroma_weight: float = 0.7

    def _get_relevant_documents(
        self, query: str, *, run_manager: CallbackManagerForRetrieverRun
    ) -> List[Document]:
        bm25_results = self.bm25.invoke(query)
        chroma_results = self.chroma.invoke(query)
        return _rrf_merge(
            [bm25_results, chroma_results],
            [self.bm25_weight, self.chroma_weight],
            self.top_k,
        )


def build_hybrid_retriever(
    vectorstore: Chroma,
    role: str,
    top_k: int = None,
) -> Union[HybridRetriever, _EmptyRetriever]:
    """Return a hybrid BM25 (0.3) + ChromaDB vector (0.7) retriever scoped to `role`.

    BM25 is built on the role-filtered corpus so warehouse cannot receive
    customer documents even through lexical matching.
    """
    top_k = top_k or int(os.getenv("TOP_K", "3"))
    role_filter = {f"role_{role}": True}

    result = vectorstore._collection.get(
        where=role_filter,
        include=["documents", "metadatas"],
    )
    docs: List[Document] = [
        Document(page_content=text, metadata=meta)
        for text, meta in zip(result["documents"], result["metadatas"])
    ]

    if not docs:
        return _EmptyRetriever()

    bm25 = BM25Retriever.from_documents(docs, k=top_k)
    chroma = vectorstore.as_retriever(
        search_type="similarity",
        search_kwargs={"k": top_k, "filter": role_filter},
    )
    return HybridRetriever(bm25=bm25, chroma=chroma, top_k=top_k)
