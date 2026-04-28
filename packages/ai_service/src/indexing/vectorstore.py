import os
from typing import Dict, List

from langchain_chroma import Chroma
from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings


def get_vectorstore(embedding: Embeddings, db_path: str = None) -> Chroma:
    db_path = db_path or os.getenv("CHROMA_DB_PATH", "./db")
    return Chroma(persist_directory=db_path, embedding_function=embedding)


def build_vectorstore(
    documents: List[Document],
    embedding: Embeddings,
    db_path: str = None,
) -> Chroma:
    """Full rebuild: create ChromaDB from documents and persist to disk."""
    db_path = db_path or os.getenv("CHROMA_DB_PATH", "./db")
    return Chroma.from_documents(
        documents=documents,
        embedding=embedding,
        persist_directory=db_path,
    )


def get_indexed_mtimes(vectorstore: Chroma) -> Dict[str, float]:
    """Return {source_path: mtime} for every file already in the index."""
    result = vectorstore._collection.get(include=["metadatas"])
    seen: Dict[str, float] = {}
    for meta in result["metadatas"]:
        src = meta.get("source", "")
        mtime = meta.get("mtime", 0.0)
        if src and src not in seen:
            seen[src] = float(mtime)
    return seen


def delete_by_source(vectorstore: Chroma, source: str) -> None:
    """Remove all chunks that came from a given source file."""
    result = vectorstore._collection.get(where={"source": source}, include=[])
    ids = result.get("ids", [])
    if ids:
        vectorstore._collection.delete(ids=ids)


def add_documents(vectorstore: Chroma, documents: List[Document]) -> None:
    """Add new chunks to an existing ChromaDB."""
    vectorstore.add_documents(documents)
