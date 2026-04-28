import os
from typing import List

import frontmatter
from langchain_community.document_loaders import DirectoryLoader, TextLoader
from langchain_core.documents import Document


def load_markdown_docs(directory: str) -> List[Document]:
    """Load all .md files from directory, extracting YAML frontmatter as metadata."""
    if not os.path.isdir(directory):
        raise FileNotFoundError(f"Docs directory not found: {directory}")

    loader = DirectoryLoader(
        directory,
        glob="**/*.md",
        loader_cls=TextLoader,
        loader_kwargs={"encoding": "utf-8"},
        show_progress=True,
    )
    raw_docs = loader.load()

    enriched: List[Document] = []
    for doc in raw_docs:
        source = doc.metadata.get("source", "")
        mtime = os.path.getmtime(source) if source and os.path.isfile(source) else 0.0
        try:
            post = frontmatter.loads(doc.page_content)
            meta = dict(post.metadata)
            meta["source"] = source
            meta["filename"] = os.path.basename(source)
            meta["mtime"] = mtime
            enriched.append(Document(page_content=post.content, metadata=meta))
        except Exception:
            doc.metadata["filename"] = os.path.basename(source)
            doc.metadata["mtime"] = mtime
            enriched.append(doc)

    return enriched
