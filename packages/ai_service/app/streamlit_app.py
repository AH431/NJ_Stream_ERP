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
from src.retrieval.prompt import RAG_PROMPT
from src.retrieval.retriever import get_retriever
from src.utils.vram_monitor import get_vram_used_gb


@st.cache_resource(show_spinner="載入模型中...")
def load_rag_components():
    db_path = os.getenv("CHROMA_DB_PATH", "./db")
    embeddings = get_embeddings()
    vectorstore = get_vectorstore(embeddings, db_path=db_path)
    retriever = get_retriever(vectorstore)
    llm = get_llm()
    chain = RAG_PROMPT | llm
    return retriever, chain


def format_docs(docs) -> str:
    return "\n\n---\n\n".join(
        f"[{d.metadata.get('filename', '?')}]\n{d.page_content}" for d in docs
    )


st.set_page_config(page_title="NJ Stream ERP 知識庫", layout="wide")
st.title("NJ Stream ERP — RAG 問答系統")

with st.sidebar:
    st.header("系統資訊")
    vram_used = get_vram_used_gb()
    vram_max = 6.0
    threshold = float(os.getenv("VRAM_THRESHOLD", "5.5"))
    st.metric("GPU VRAM", f"{vram_used:.1f} / {vram_max:.0f} GB")
    st.progress(min(vram_used / vram_max, 1.0))
    if vram_used >= threshold:
        st.warning(f"VRAM 接近上限 ({threshold} GB)")
    st.divider()
    st.caption(f"LLM: {os.getenv('OLLAMA_MODEL', 'llama3.2:3b')}")
    st.caption(f"Embedding: {os.getenv('EMBEDDING_MODEL', 'bge-m3')}")
    st.caption(f"Top-K: {os.getenv('TOP_K', '3')}")
    if st.button("重新整理 VRAM"):
        st.rerun()

retriever, chain = load_rag_components()

if "messages" not in st.session_state:
    st.session_state.messages = []

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])
        if msg["role"] == "assistant" and msg.get("sources"):
            with st.expander("參考來源"):
                for s in msg["sources"]:
                    st.markdown(f"**{s['filename']}**")
                    st.text(s["snippet"])

if question := st.chat_input("請輸入問題..."):
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        with st.spinner("搜尋知識庫中..."):
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
            with st.expander("參考來源"):
                for s in sources:
                    st.markdown(f"**{s['filename']}**")
                    st.text(s["snippet"])

    st.session_state.messages.append(
        {"role": "assistant", "content": answer, "sources": sources}
    )
