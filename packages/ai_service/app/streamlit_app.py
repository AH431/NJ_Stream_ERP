"""Streamlit RAG Q&A App"""
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import streamlit as st

from src.indexing.embedder import get_embeddings
from src.indexing.vectorstore import get_vectorstore
from src.llm.ollama_client import get_llm
from src.rag.prompt import RAG_PROMPT
from src.rag.retriever import build_hybrid_retriever
from src.utils.vram_monitor import get_vram_used_gb


def _s(zh: str, en: str) -> str:
    return en if st.session_state.get("lang") == "en" else zh


@st.cache_resource(show_spinner="Loading model...")
def load_rag_components():
    db_path = os.getenv("CHROMA_DB_PATH", "./db")
    embeddings = get_embeddings()
    vectorstore = get_vectorstore(embeddings, db_path=db_path)
    retriever = build_hybrid_retriever(vectorstore, role="admin")
    llm = get_llm()
    chain = RAG_PROMPT | llm
    return retriever, chain


def format_docs(docs) -> str:
    return "\n\n---\n\n".join(
        f"[{d.metadata.get('filename', '?')}]\n{d.page_content}" for d in docs
    )


st.set_page_config(page_title="NJ Stream ERP Knowledge Base", layout="wide")

if "lang" not in st.session_state:
    st.session_state.lang = "zh"

# Sidebar — language toggle must come first so _s() reflects the chosen lang
with st.sidebar:
    lang_choice = st.radio(
        "Language",
        options=["中文", "English"],
        index=1 if st.session_state.lang == "en" else 0,
        horizontal=True,
        label_visibility="collapsed",
    )
    st.session_state.lang = "en" if lang_choice == "English" else "zh"
    st.divider()

    st.header(_s("系統資訊", "System Info"))
    vram_used = get_vram_used_gb()
    vram_max = 6.0
    threshold = float(os.getenv("VRAM_THRESHOLD", "5.5"))
    st.metric("GPU VRAM", f"{vram_used:.1f} / {vram_max:.0f} GB")
    st.progress(min(vram_used / vram_max, 1.0))
    if vram_used >= threshold:
        st.warning(_s(f"VRAM 接近上限 ({threshold} GB)", f"VRAM near limit ({threshold} GB)"))
    st.divider()
    st.caption(f"LLM: {os.getenv('OLLAMA_MODEL', 'llama3.2:3b')}")
    st.caption(f"Embedding: {os.getenv('EMBEDDING_MODEL', 'mxbai-embed-large')}")
    st.caption(f"Top-K: {os.getenv('TOP_K', '3')}")
    if st.button(_s("重新整理 VRAM", "Refresh VRAM")):
        st.rerun()

st.title("NJ Stream ERP — " + _s("RAG 問答系統", "RAG Q&A"))

retriever, chain = load_rag_components()

if "messages" not in st.session_state:
    st.session_state.messages = []

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])
        if msg["role"] == "assistant" and msg.get("sources"):
            with st.expander(_s("參考來源", "Sources")):
                for src in msg["sources"]:
                    st.markdown(f"**{src['filename']}**")
                    st.text(src["snippet"])

if question := st.chat_input(_s("請輸入問題...", "Ask a question...")):
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        with st.spinner(_s("搜尋知識庫中...", "Searching knowledge base...")):
            docs = retriever.invoke(question)
            context = format_docs(docs)
            response = chain.invoke({"context": context, "question": question})
            answer = response.content if hasattr(response, "content") else str(response)

        st.markdown(answer)
        sources = [
            {"filename": d.metadata.get("filename", "?"), "snippet": d.page_content[:200]}
            for d in docs
        ]
        if sources:
            with st.expander(_s("參考來源", "Sources")):
                for src in sources:
                    st.markdown(f"**{src['filename']}**")
                    st.text(src["snippet"])

    st.session_state.messages.append(
        {"role": "assistant", "content": answer, "sources": sources}
    )
