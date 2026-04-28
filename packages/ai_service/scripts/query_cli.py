"""
Interactive RAG Q&A CLI.
Usage:
    python scripts/query_cli.py
    python scripts/query_cli.py --k 5
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
from src.llm.ollama_client import get_llm
from src.retrieval.prompt import RAG_PROMPT
from src.retrieval.retriever import get_retriever
from src.utils.logger import get_logger

logger = get_logger(__name__)


def format_docs(docs) -> str:
    return "\n\n---\n\n".join(
        f"[{d.metadata.get('filename', '?')}]\n{d.page_content}" for d in docs
    )


def main(k: int = None) -> None:
    db_path = os.getenv("CHROMA_DB_PATH", "./db")
    logger.info("Loading embeddings and vectorstore...")
    embeddings = get_embeddings()
    vectorstore = get_vectorstore(embeddings, db_path=db_path)
    retriever = get_retriever(vectorstore, k=k)
    llm = get_llm()
    chain = RAG_PROMPT | llm

    print("\n=== RAG 問答系統（輸入 quit 離開）===\n")
    while True:
        try:
            question = input("問題: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n離開")
            break
        if question.lower() in ("quit", "exit", "q"):
            break
        if not question:
            continue

        docs = retriever.invoke(question)
        context = format_docs(docs)
        response = chain.invoke({"context": context, "question": question})
        answer = response.content if hasattr(response, "content") else str(response)

        print(f"\n回答:\n{answer}\n")
        print("參考來源:")
        for d in docs:
            print(f"  - {d.metadata.get('filename', '?')}")
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--k", type=int, default=None, help="Number of retrieved chunks")
    args = parser.parse_args()
    main(k=args.k)
