import os
from typing import Any, Dict, Optional

from langchain_chroma import Chroma
from langchain_core.vectorstores import VectorStoreRetriever


def get_retriever(
    vectorstore: Chroma,
    k: int = None,
    search_type: str = "similarity",
    filter: Optional[Dict[str, Any]] = None,
) -> VectorStoreRetriever:
    k = k or int(os.getenv("TOP_K", "3"))
    search_kwargs: Dict[str, Any] = {"k": k}
    if filter:
        search_kwargs["filter"] = filter
    return vectorstore.as_retriever(
        search_type=search_type,
        search_kwargs=search_kwargs,
    )
