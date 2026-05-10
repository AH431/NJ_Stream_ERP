import os

from langchain_ollama import OllamaEmbeddings


def get_embeddings(model_name: str = None) -> OllamaEmbeddings:
    model_name = model_name or os.getenv("EMBEDDING_MODEL", "mxbai-embed-large")
    return OllamaEmbeddings(model=model_name)
