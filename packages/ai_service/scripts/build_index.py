"""
Build or incrementally update the ChromaDB index from Markdown files.

Full rebuild (first time):
    python scripts/build_index.py --docs-dir data/knowledge_cards

Incremental update (add/update changed files only):
    python scripts/build_index.py --docs-dir data/knowledge_cards --incremental
"""
import argparse
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from langchain_core.documents import Document

from src.indexing.embedder import get_embeddings
from src.indexing.vectorstore import (
    add_documents,
    build_vectorstore,
    delete_by_source,
    get_indexed_mtimes,
    get_vectorstore,
)
from src.ingest.cleaner import clean_markdown
from src.ingest.loader import load_markdown_docs
from src.ingest.splitter import split_documents
from src.utils.logger import get_logger

logger = get_logger(__name__)


def _inject_card_context(chunks: list) -> list:
    """Two-pass: collect per-card inventory/price/contact, then prepend a summary
    header to every non-summary chunk so the LLM can read key facts from any chunk.
    """
    # Pass 1 — collect context facts per card
    card_ctx: dict = defaultdict(lambda: {
        "sku": "", "status": "", "price": "", "contact": "", "customer": "", "payment": "",
    })

    for chunk in chunks:
        meta = chunk.metadata
        src = meta.get("filename") or meta.get("source", "")
        section = meta.get("h2", "")
        text = chunk.page_content

        if meta.get("sku"):
            card_ctx[src]["sku"] = meta["sku"]

        if section == "Inventory Status":
            m_status = re.search(r'\*\*Status\*\*:\s*(.+)', text)
            m_avail  = re.search(r'\*\*Available\*\*:\s*(\d+)', text)
            m_safety = re.search(r'\*\*Safety Level\*\*:\s*(\d+)', text)
            if m_status:
                status = m_status.group(1).strip()
                if m_avail and m_safety:
                    status = f"{status} ({m_avail.group(1)} avail / {m_safety.group(1)} safety)"
                card_ctx[src]["status"] = status

        if section == "Pricing":
            m = re.search(r'\*\*Unit Price\*\*:\s*(\S+)', text)
            if m:
                card_ctx[src]["price"] = m.group(1).strip()

        if section == "Customer Identity":
            m = re.search(r'\*\*Name\*\*:\s*(.+)', text)
            if m:
                card_ctx[src]["customer"] = m.group(1).strip()

        if section == "Contact Summary":
            m = re.search(r'\*\*Primary Contact\*\*:\s*(.+)', text)
            if m:
                card_ctx[src]["contact"] = m.group(1).strip()

        if section == "Payment Terms":
            m = re.search(r'\*\*Net Days\*\*:\s*(.+)', text)
            if m:
                card_ctx[src]["payment"] = f"Net {m.group(1).strip()}"

    # Sections whose content already carries the relevant fact — skip injection
    _SKIP = {"Inventory Status", "Pricing", "Contact Summary"}

    # Pass 2 — prepend header line to every eligible chunk
    enriched = []
    for chunk in chunks:
        meta = chunk.metadata
        src = meta.get("filename") or meta.get("source", "")
        section = meta.get("h2", "")
        ctx = card_ctx.get(src, {})

        if section in _SKIP or not any(ctx.values()):
            enriched.append(chunk)
            continue

        sku = ctx.get("sku") or meta.get("sku", "")
        if sku:
            parts = [f"Card: {sku}"]
            if ctx.get("status"):
                parts.append(f"Inventory: {ctx['status']}")
            if ctx.get("price"):
                parts.append(f"Unit Price: {ctx['price']}")
        else:
            parts = [f"Card: {ctx.get('customer') or src}"]
            if ctx.get("contact"):
                parts.append(f"Contact: {ctx['contact']}")
            if ctx.get("payment"):
                parts.append(f"Payment: {ctx['payment']}")

        header = "[" + " | ".join(parts) + "]"
        enriched.append(Document(
            page_content=header + "\n\n" + chunk.page_content,
            metadata=chunk.metadata,
        ))

    return enriched


def _prepare_chunks(
    docs: list,
    chunk_size: int,
    chunk_overlap: int,
) -> list:
    cleaned = [
        Document(page_content=clean_markdown(doc.page_content), metadata=doc.metadata)
        for doc in docs
    ]
    cleaned = [d for d in cleaned if d.page_content.strip()]
    chunks = split_documents(cleaned, chunk_size=chunk_size, chunk_overlap=chunk_overlap)
    chunks = _inject_card_context(chunks)
    # Keep minimum 30 chars — preserves short sections (Pricing ~34, Contact ~54)
    # while still dropping near-empty chunks (e.g. "## Last Updated\n2026-05-03" ~23 chars)
    return [c for c in chunks if len(c.page_content.strip()) >= 30]


def build_index(
    docs_dir: str = "data/knowledge_cards",
    db_path: str = None,
    embedding_model: str = None,
    chunk_size: int = None,
    chunk_overlap: int = None,
    incremental: bool = False,
) -> None:
    db_path = db_path or os.getenv("CHROMA_DB_PATH", "./db")
    chunk_size = chunk_size or int(os.getenv("CHUNK_SIZE", 800))
    chunk_overlap = chunk_overlap or int(os.getenv("CHUNK_OVERLAP", 100))

    logger.info(f"Loading embedding model...")
    embeddings = get_embeddings(model_name=embedding_model)

    if not incremental:
        logger.info(f"Full rebuild — loading all .md files from: {docs_dir}")
        docs = load_markdown_docs(docs_dir)
        logger.info(f"Loaded {len(docs)} documents")
        chunks = _prepare_chunks(docs, chunk_size, chunk_overlap)
        logger.info(f"Total chunks: {len(chunks)} — writing to {db_path}")
        build_vectorstore(chunks, embeddings, db_path=db_path)
        logger.info("Done")
        return

    # ── Incremental mode ────────────────────────────────────────────────────
    logger.info("Incremental mode — checking for new / modified files...")
    vectorstore = get_vectorstore(embeddings, db_path=db_path)
    indexed_mtimes = get_indexed_mtimes(vectorstore)

    docs_path = Path(docs_dir)
    all_md_files = list(docs_path.rglob("*.md"))
    if not all_md_files:
        logger.warning(f"No .md files found in {docs_dir}")
        return

    to_update: list[Path] = []
    for f in all_md_files:
        current_mtime = f.stat().st_mtime
        indexed_mtime = indexed_mtimes.get(str(f), None)
        if indexed_mtime is None:
            logger.info(f"  [NEW]      {f.name}")
            to_update.append(f)
        elif abs(current_mtime - indexed_mtime) > 1:  # >1 s tolerance
            logger.info(f"  [MODIFIED] {f.name}")
            to_update.append(f)
        else:
            logger.info(f"  [SKIP]     {f.name}")

    if not to_update:
        logger.info("Nothing to update — index is up to date")
        return

    logger.info(f"{len(to_update)} file(s) to (re)index")

    import frontmatter as fm
    from langchain_core.documents import Document as LCDoc

    new_docs: list[LCDoc] = []
    for f in to_update:
        try:
            text = f.read_text(encoding="utf-8")
            post = fm.loads(text)
            meta = dict(post.metadata)
            meta["source"] = str(f)
            meta["filename"] = f.name
            meta["mtime"] = f.stat().st_mtime
            new_docs.append(LCDoc(page_content=post.content, metadata=meta))
        except Exception as e:
            logger.warning(f"Failed to load {f}: {e}")
            continue

    chunks = _prepare_chunks(new_docs, chunk_size, chunk_overlap)

    for chunk in chunks:
        if "mtime" not in chunk.metadata and chunk.metadata.get("source"):
            src = Path(chunk.metadata["source"])
            if src.exists():
                chunk.metadata["mtime"] = src.stat().st_mtime

    for f in to_update:
        delete_by_source(vectorstore, str(f))

    add_documents(vectorstore, chunks)
    logger.info(f"Done — added {len(chunks)} chunks for {len(to_update)} file(s)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build/update ChromaDB index from Markdown files")
    parser.add_argument("--docs-dir", default="data/knowledge_cards")
    parser.add_argument("--db-path", default=None)
    parser.add_argument("--embedding-model", default=None)
    parser.add_argument("--chunk-size", type=int, default=None)
    parser.add_argument("--chunk-overlap", type=int, default=None)
    parser.add_argument(
        "--incremental",
        action="store_true",
        help="Only (re)index new or modified files instead of full rebuild",
    )
    args = parser.parse_args()

    build_index(
        docs_dir=args.docs_dir,
        db_path=args.db_path,
        embedding_model=args.embedding_model,
        chunk_size=args.chunk_size,
        chunk_overlap=args.chunk_overlap,
        incremental=args.incremental,
    )
