# 工作日誌

---

## 2026-04-26

### 完成事項
- **第一階段實作**：完成 ingest → indexing pipeline 所有核心模組

| 檔案 | 說明 |
|------|------|
| `src/utils/logger.py` | 統一 logging，輸出至 console + `logs/rag.log` |
| `src/ingest/loader.py` | DirectoryLoader 封裝，自動解析 YAML frontmatter |
| `src/ingest/cleaner.py` | 清除圖片連結、裸 URL、[toc]，保留 markdown 文字連結 |
| `src/ingest/splitter.py` | 雙層切分：MarkdownHeaderTextSplitter → RecursiveCharacterTextSplitter |
| `src/indexing/embedder.py` | HuggingFaceEmbeddings，自動偵測 CUDA |
| `src/indexing/vectorstore.py` | ChromaDB build/load 封裝 |
| `scripts/build_index.py` | 完整 pipeline 整合腳本，支援 CLI 參數與 .env |
| `tests/test_cleaner.py` | 8 個單元測試 |
| `tests/test_splitter.py` | 6 個單元測試 |
| `requirements.txt` | 補上 `python-dotenv` |

### 進行中
- 安裝 Ollama（本機 LLM 環境）

### 待辦（第二階段）
- [ ] `src/llm/ollama_client.py` — ChatOllama 封裝
- [ ] `src/retrieval/retriever.py` — ChromaDB retriever 設定
- [ ] `src/retrieval/prompt.py` — 繁體中文防幻覺 prompt template
- [ ] `scripts/query_cli.py` — 問答 CLI
- [ ] `tests/test_retrieval.py` — 檢索流程測試
- [ ] `app/streamlit_app.py` — Streamlit UI

### Ollama Embedding 模型選型
決定 pull 三個 embedding 模型，保留彈性因應未來可能新增英文資料：

| 模型 | 大小 | 特性 |
|------|------|------|
| `nomic-embed-text` | ~274MB | 輕量快速，適合英文 |
| `mxbai-embed-large` | ~670MB | 準確度與速度平衡 |
| `bge-m3` | ~1.2GB | 多語言強（繁中首選） |

```bash
ollama pull nomic-embed-text
ollama pull mxbai-embed-large
ollama pull bge-m3
```

目前預設仍使用 HuggingFace `paraphrase-multilingual-MiniLM-L12-v2`，Ollama embedding 作為備選方案待第二階段評估切換。

### 環境配置
- 硬體：Win10, RTX 2060 6GB VRAM, 16GB RAM
- LLM：Ollama `llama3.2:3b`（已安裝）
- Embedding：`sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`（主）/ Ollama bge-m3（備）
- Vector DB：ChromaDB persistent（`./db`）
- chunk_size=800, chunk_overlap=100, top_k=3

---
