import os

from langchain_ollama import ChatOllama


def get_llm() -> ChatOllama:
    return ChatOllama(
        model=os.getenv("OLLAMA_MODEL", "llama3.2:3b"),
        num_ctx=int(os.getenv("OLLAMA_NUM_CTX", "8192")),
        temperature=float(os.getenv("OLLAMA_TEMPERATURE", "0.3")),
    )
