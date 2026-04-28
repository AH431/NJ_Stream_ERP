from typing import List

from langchain_core.documents import Document
from langchain_text_splitters import MarkdownHeaderTextSplitter, RecursiveCharacterTextSplitter

_HEADERS_TO_SPLIT_ON = [
    ("#", "h1"),
    ("##", "h2"),
    ("###", "h3"),
]


def split_documents(
    docs: List[Document],
    chunk_size: int = 800,
    chunk_overlap: int = 100,
) -> List[Document]:
    """Two-pass split: header-aware first, then character split for oversized chunks."""
    header_splitter = MarkdownHeaderTextSplitter(
        headers_to_split_on=_HEADERS_TO_SPLIT_ON,
        strip_headers=False,
    )
    char_splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
    )

    chunks: List[Document] = []
    for doc in docs:
        header_splits = header_splitter.split_text(doc.page_content)
        for split in header_splits:
            # Inherit parent metadata for keys not set by the header splitter
            for k, v in doc.metadata.items():
                split.metadata.setdefault(k, v)
            if len(split.page_content) > chunk_size:
                chunks.extend(char_splitter.split_documents([split]))
            else:
                chunks.append(split)
    return chunks
