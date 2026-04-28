from langchain_core.documents import Document

from src.ingest.splitter import split_documents


def _doc(content: str, **meta) -> Document:
    return Document(page_content=content, metadata={"source": "test.md", **meta})


def test_basic_split_returns_chunks():
    doc = _doc("# 標題一\n\n這是第一段。\n\n## 子標題\n\n子標題的內容。")
    chunks = split_documents([doc])
    assert len(chunks) >= 1


def test_header_stored_in_metadata():
    doc = _doc("# 主標題\n\n正文內容在這裡。")
    chunks = split_documents([doc])
    assert chunks[0].metadata.get("h1") == "主標題"


def test_parent_metadata_inherited():
    doc = _doc("# 標題\n\n內容。", tags=["AI", "RAG"])
    chunks = split_documents([doc])
    for chunk in chunks:
        assert chunk.metadata.get("tags") == ["AI", "RAG"]
        assert chunk.metadata.get("source") == "test.md"


def test_long_chunk_is_further_split():
    long_content = "這是一段測試文字。" * 200  # ~1800 chars, well over 800
    doc = _doc(f"# 長文標題\n\n{long_content}")
    chunks = split_documents([doc], chunk_size=800, chunk_overlap=100)
    assert len(chunks) > 1
    for chunk in chunks:
        assert len(chunk.page_content) < 1600


def test_empty_docs_list():
    assert split_documents([]) == []


def test_multiple_docs():
    docs = [
        _doc("# Doc A\n\n內容A。", filename="a.md"),
        _doc("# Doc B\n\n內容B。", filename="b.md"),
    ]
    chunks = split_documents(docs)
    filenames = {c.metadata.get("filename") for c in chunks}
    assert "a.md" in filenames
    assert "b.md" in filenames
