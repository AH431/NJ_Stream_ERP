"""
Validate ChromaDB index: print chunk count, sample metadata, run test query.
Usage:
    python scripts/validate_index.py
    python scripts/validate_index.py --test-query "IC-8800規格是什麼?"
"""
import argparse
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.indexing.embedder import get_embeddings
from src.indexing.vectorstore import get_vectorstore
from src.retrieval.retriever import get_retriever


def main(test_query: str = "什麼是RAG?") -> None:
    db_path = os.getenv("CHROMA_DB_PATH", "./db")
    print(f"ChromaDB: {db_path}")

    embeddings = get_embeddings()
    vectorstore = get_vectorstore(embeddings, db_path=db_path)
    collection = vectorstore._collection
    count = collection.count()
    print(f"Total chunks: {count}")

    if count == 0:
        print("Index is empty — run build_index.py first")
        return

    sample = collection.get(limit=3, include=["documents", "metadatas"])
    print("\nSample chunks:")
    for i, (doc, meta) in enumerate(zip(sample["documents"], sample["metadatas"])):
        print(f"\n[{i + 1}] metadata: {meta}")
        print(f"    content: {doc[:120]}...")

    retriever = get_retriever(vectorstore, k=2)
    results = retriever.invoke(test_query)
    print(f"\nTest query: '{test_query}'")
    for r in results:
        print(f"  - {r.metadata.get('filename', '?')}: {r.page_content[:100]}...")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-query", default="什麼是RAG?")
    args = parser.parse_args()
    main(test_query=args.test_query)
