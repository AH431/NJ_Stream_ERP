# Phase 3 PRD v5.0：手機 AI 助理 × ERP 即時問答系統

> **版本**：v5.0 — 2026-04-28
> **基礎**：V4_codex 全部內容 + codebase 實際掃描後的補充修正
> **定位**：可直接交給開發者執行的完整規格，補上 V4 留下的架構缺口與實作細節
> **核心優先序**：資料安全與可還原 > 權限與稽核 > 動態資料正確性 > AI 體驗

---

## 一、版本沿革與 v5.0 新增內容

### 1.1 各版本定位

| 版本 | 主要貢獻 |
|---|---|
| v1.0 | Phase 3 實作藍圖，完整架構設計 |
| V2_codex | 安全邊界、備份/還原/audit log |
| v3.0 | 整合 v1.0 + V2，修正 JWT/path，接近上線規格 |
| V4_codex | 修正「範例與 codebase 不貼合」的踩坑點，拆成可執行小目標 |
| **v5.0** | 掃描現有 codebase 後補上 V4 留下的六個架構缺口，加入測試策略、完整 env 清單、服務間通訊細節 |

### 1.2 v5.0 新增的六個補充

| # | 缺口 | v5.0 解法 |
|---|---|---|
| A | ai_service 套件結構未定義 | 定義完整目錄結構與 Dockerfile |
| B | JWT 轉發機制未說明 | 明確 Fastify→ai_service→Fastify 的 token 流 |
| C | ai_service 與 Fastify 間無 internal auth | 加入 `X-Internal-Token` header |
| D | audit_logs 與 processed_operations 邊界不清 | 明確兩表職責，不混用 |
| E | 完整 env vars 清單缺失 | 補充所有新增變數及預設值 |
| F | 測試策略與驗收條件分散 | 每個 PR 明確最低測試需求 |

---

## 二、系統架構總覽

### 2.1 請求流程

```
[手機 Flutter App]
        │
        │  HTTPS  Authorization: Bearer <JWT>
        ▼
[Fastify /api/v1/ai/chat]
  ├── verifyJwt (plugins/auth.plugin.ts)
  ├── rate limit 10 req/min/user
  ├── createAuditLog status=pending
  ├── forward JWT + question to ai_service
  │
  │  HTTP (Docker internal network)
  │  X-Internal-Token: <AI_SERVICE_INTERNAL_TOKEN>
  │  Body: { question, userJwt, role }
  ▼
[ai_service /chat  (FastAPI, internal only)]
  ├── verify X-Internal-Token
  ├── query router → static / dynamic / blocked
  │
  ├── [static]  → Chroma retriever → prompt → Ollama stream
  │
  ├── [dynamic] → tool caller
  │     ├── query parser (SKU regex / ID regex)
  │     └── Fastify read endpoint
  │           Authorization: Bearer <userJwt>  ← 轉發使用者 JWT
  │           GET /api/v1/products/search
  │           GET /api/v1/inventory
  │           GET /api/v1/customers/:id
  │           GET /api/v1/quotations/:id
  │           GET /api/v1/sales-orders/:id
  │
  └── [blocked] → 固定拒絕回應，不呼叫 LLM
        │
        ▼  SSE  data: {"type":"token","content":"..."}
[Fastify SSE proxy]
  ├── stream forward to Flutter
  ├── client abort → cancel upstream
  └── finishAuditLog status=success/blocked/error
        │
        ▼
[Flutter AiProvider]
  └── LineSplitter buffer → stream tokens → ChatScreen
```

### 2.2 資料流邊界規則（不可破壞）

| 規則 | 說明 |
|---|---|
| ai_service runtime 不直接碰 DB | 只透過 Fastify read endpoints 取資料 |
| Fastify 是唯一對外入口 | ai_service 無對外 port |
| 動態資料不進 RAG | 庫存、報價、訂單答案必須從 Fastify API 即時查詢 |
| Indexing job 用 read-only DB user | card_generator.py 不用 app DB user |
| audit log 必須在請求結束前完成 | 不可省略，即使 AI service 失敗也要記錄 error |

---

## 三、套件結構定義（v5.0 新增）

### 3.1 Monorepo 目錄

```
c:\Projects\NJ_Stream_ERP\
├── packages/
│   ├── backend/                 ← 現有 Fastify backend
│   ├── frontend/                ← 現有 Flutter app
│   └── ai_service/              ← Phase 3 新增（本節定義）
├── scripts/
│   ├── backup_pg.ps1            ← M0.3 新增
│   └── restore_pg.ps1           ← M0.3 新增
├── docs/
│   └── artifacts/
│       └── phase3-ai-golden-questions.md  ← M0.5 新增
├── docker-compose.yml
└── docker-compose.prod.yml      ← 需加入 ai_service service
```

### 3.2 ai_service 完整目錄結構

```
packages/ai_service/
├── Dockerfile
├── requirements.txt
├── .env.example
├── main.py                      ← FastAPI entry point
└── src/
    ├── api/
    │   └── chat.py              ← POST /chat SSE endpoint
    ├── router/
    │   └── query_router.py      ← static / dynamic / blocked 分類
    ├── tools/
    │   ├── query_parser.py      ← SKU / ID regex 抽取
    │   ├── erp_tools.py         ← tool caller (帶 JWT 呼叫 Fastify)
    │   └── formatters.py        ← deterministic answer template
    ├── rag/
    │   ├── retriever.py         ← hybrid retriever (vector + BM25)
    │   └── prompt.py            ← prompt policy
    ├── llm/
    │   └── ollama_client.py     ← fake mode / real mode
    └── indexing/
        ├── schema_mapping.md    ← Drizzle schema → card field mapping
        ├── card_generator.py    ← 產生卡片，用 read-only DB user
        └── build_index.py       ← 建立 Chroma index
```

### 3.3 ai_service Dockerfile

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 3.4 docker-compose.prod.yml 補充 ai_service

```yaml
services:
  # ... 現有 postgres, migration, backend ...

  ai_service:
    build: ./packages/ai_service
    restart: unless-stopped
    networks:
      - internal            # 只在 internal network，無 ports 對外
    environment:
      - AI_FAKE_LLM=${AI_FAKE_LLM:-false}
      - OLLAMA_BASE_URL=${OLLAMA_BASE_URL}
      - OLLAMA_MODEL=${OLLAMA_MODEL:-llama3}
      - CHROMA_PATH=/data/chroma
      - FASTIFY_INTERNAL_URL=http://backend:3000
      - AI_SERVICE_INTERNAL_TOKEN=${AI_SERVICE_INTERNAL_TOKEN}
      - DB_READONLY_URL=${DB_READONLY_URL}
    volumes:
      - chroma_data:/data/chroma
    depends_on:
      - backend

volumes:
  chroma_data:
```

---

## 四、服務間通訊與 JWT 轉發（v5.0 新增）

### 4.1 Fastify → ai_service：轉發格式

```ts
// packages/backend/src/routes/ai.route.ts
// Fastify 打 ai_service 時帶的 request body
interface AiServiceRequest {
  question: string;
  userJwt: string;    // 從 request.headers.authorization 取出，去掉 'Bearer '
  role: string;       // 從 request.user.role 取
  userId: number;     // 從 request.user.userId 取
  requestId: string;  // audit log 的 id，供 tool audit 對應
}
```

Header 加：

```ts
headers: {
  'X-Internal-Token': process.env.AI_SERVICE_INTERNAL_TOKEN,
  'Content-Type': 'application/json',
}
```

### 4.2 ai_service 驗證 internal token

```python
# packages/ai_service/src/api/chat.py
from fastapi import Header, HTTPException
import os

INTERNAL_TOKEN = os.environ["AI_SERVICE_INTERNAL_TOKEN"]

async def verify_internal(x_internal_token: str = Header(...)):
    if x_internal_token != INTERNAL_TOKEN:
        raise HTTPException(status_code=403, detail="forbidden")
```

### 4.3 ai_service tool caller 帶使用者 JWT 回打 Fastify

```python
# packages/ai_service/src/tools/erp_tools.py
import httpx, os

FASTIFY_URL = os.environ["FASTIFY_INTERNAL_URL"]

async def call_fastify(path: str, user_jwt: str) -> dict:
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{FASTIFY_URL}{path}",
            headers={"Authorization": f"Bearer {user_jwt}"},
            timeout=10.0,
        )
        resp.raise_for_status()
        return resp.json()
```

### 4.4 安全規則

- `AI_SERVICE_INTERNAL_TOKEN` 長度不得少於 32 字元，可用 `openssl rand -hex 32` 產生
- ai_service 收到請求時**先驗 X-Internal-Token**，再處理 userJwt
- ai_service 不自己簽發 JWT，只轉發來自 Flutter 的使用者 token
- userJwt 的有效期由 Fastify auth plugin 已驗過，ai_service 不需再次驗簽

---

## 五、Audit 表格設計（v5.0 明確邊界）

### 5.1 兩表職責分離

| 表 | 職責 | 寫入時機 |
|---|---|---|
| `processed_operations` | sync/push 操作的稽核（**保持原狀，不動**） | sync.service.ts |
| `audit_logs`（新增）| AI chat、AI tool call、blocked query、admin import | ai.route.ts、audit.service.ts |

**重要**：這兩張表不混用，不共享 writer。

### 5.2 audit_logs Drizzle schema

```ts
// packages/backend/src/schemas/audit_logs.schema.ts
import { pgTable, serial, integer, text, timestamp, jsonb } from 'drizzle-orm/pg-core';

export const auditLogs = pgTable('audit_logs', {
  id:           serial('id').primaryKey(),
  requestId:    text('request_id').notNull(),          // UUID，一次 ai.chat 全程共用
  userId:       integer('user_id').notNull(),
  userRole:     text('user_role').notNull(),
  action:       text('action').notNull(),              // 見 5.3
  resourceType: text('resource_type'),                 // product / inventory / quotation ...
  resourceId:   text('resource_id'),
  questionHash: text('question_hash'),                 // SHA-256，用於去識別化統計
  toolName:     text('tool_name'),                     // ai.tool_call 時填寫
  status:       text('status').notNull(),              // 見 5.4
  errorMessage: text('error_message'),
  meta:         jsonb('meta'),                         // 額外結構化資料
  createdAt:    timestamp('created_at', { mode: 'date' }).defaultNow().notNull(),
  finishedAt:   timestamp('finished_at', { mode: 'date' }),
});
```

### 5.3 action 枚舉

```text
ai.chat           ← 使用者發問（主事件）
ai.tool_call      ← tool caller 呼叫 Fastify read endpoint
ai.blocked        ← query router 判定 blocked
admin.import      ← CSV import
```

### 5.4 status 狀態機

```
ai.chat:
  pending → success
  pending → blocked
  pending → error

ai.tool_call:
  success | denied | error
```

```ts
// status type
type AuditStatus = 'pending' | 'success' | 'denied' | 'blocked' | 'error';
```

### 5.5 audit_logs 生命週期（ai.chat 範例）

```ts
// 1. 請求開始
const auditId = await createAuditLog({
  requestId,
  userId, userRole,
  action: 'ai.chat',
  questionHash: hashText(question),
  status: 'pending',
});

// 2. (選擇性) tool call 各自寫一筆
await logAuditEvent({
  requestId,
  userId, userRole,
  action: 'ai.tool_call',
  toolName: 'get_inventory',
  resourceType: 'inventory',
  resourceId: String(productId),
  status: 'success',
});

// 3. 請求結束
await finishAuditLog(auditId, { status: 'success', finishedAt: new Date() });
// 或
await finishAuditLog(auditId, { status: 'error', errorMessage: e.message });
```

---

## 六、完整環境變數清單（v5.0 新增）

### 6.1 Backend 新增變數

| 變數 | 說明 | 範例 |
|---|---|---|
| `AI_SERVICE_URL` | Fastify 打 ai_service 的內部 URL | `http://ai_service:8000` |
| `AI_SERVICE_INTERNAL_TOKEN` | Fastify↔ai_service mutual auth，≥32 字元 | `openssl rand -hex 32` |

### 6.2 ai_service 變數

| 變數 | 說明 | 預設值 |
|---|---|---|
| `AI_FAKE_LLM` | `true` 時不需要 Ollama，回傳固定 token stream | `false` |
| `FASTIFY_INTERNAL_URL` | ai_service 打回 Fastify 的內部 URL | `http://backend:3000` |
| `AI_SERVICE_INTERNAL_TOKEN` | 與 backend 共用同一個值 | — |
| `OLLAMA_BASE_URL` | Ollama 服務位址 | `http://localhost:11434` |
| `OLLAMA_MODEL` | 使用的模型名稱 | `llama3` |
| `CHROMA_PATH` | ChromaDB 資料目錄 | `./data/chroma` |
| `DB_READONLY_URL` | card_generator.py 使用的唯讀 DB 連線 | — |

### 6.3 備份腳本變數

| 變數 | 說明 | 範例 |
|---|---|---|
| `DATABASE_URL` | 現有，備份腳本沿用 | — |
| `BACKUP_PASSPHRASE` | GPG 對稱加密密語，≥20 字元 | — |
| `BACKUP_DIR` | 備份輸出目錄 | `C:\Backups\NJ_ERP` |

### 6.4 .env.production.example 需更新的欄位

在 M1.1 建立 ai_service 套件時，同步更新根目錄的 `.env.production.example`，加入上述所有新增變數的 placeholder。

---

## 七、V4 保留的正確架構決策

以下 V4 的決策在 v5.0 完整繼承，不重複說明：

1. Sprint 0（M0）不可跳過：備份→audit schema→AI proxy skeleton
2. Fastify 是唯一對外入口，ai_service 無 ports
3. 動態資料不由 RAG 回答，必須從 Fastify API 即時查詢
4. AI service runtime 不直接碰 DB
5. Indexing job 使用 read-only DB user
6. RAG metadata 用 `role_admin` / `role_sales` / `role_warehouse` boolean（不用 `$contains`）

---

## 八、實作細節修正（V4 原有 + v5.0 補充整合）

### 8.1 Route file 內不寫完整 path

```ts
// app.ts
app.register(aiRoutes, { prefix: '/api/v1/ai' });

// ai.route.ts ← 只寫相對路徑
app.post('/chat', { preHandler: [app.verifyJwt] }, handler);
```

### 8.2 Fastify schema 不塞 Zod object

沿用現有 handler 內 `safeParse()` 模式，不引入 `fastify-type-provider-zod`。

### 8.3 audit_logs.status 完整枚舉

```text
pending | success | denied | blocked | error
```

AI request 必須「開始寫 pending，結束 update 成最終狀態」，即使 SSE 中途失敗也要 update。

### 8.4 card_generator.py SQL 必須對照現有 Drizzle schema

現有實際欄位（source of truth：`packages/backend/src/schemas/`）：

| 表 | 可用欄位 |
|---|---|
| `products` | `id`, `name`, `sku`, `unit_price`, `cost_price`, `min_stock_level` |
| `customers` | `id`, `name`, `contact`, `email`, `tax_id`, `payment_terms_days` |
| `quotations` | `id`, `customer_id`, `created_by`, `total_amount`, `tax_amount`, `status`, `converted_to_order_id`, `created_at` |
| `inventory_items` | `product_id`, `quantity_on_hand`, `quantity_reserved`, `min_stock_level`, `alert_stock_level`, `critical_stock_level` |

**不存在的欄位（不可使用）**：`spec`, `stock_threshold`, `industry`, `contact_name`, `city`, `quote_number`, `issue_date`

### 8.5 Read endpoints 加在現有 route file

- `products/search` 加在 `products.route.ts`（已存在）
- `customers/search` 加在 `customers.route.ts`（已存在）
- `inventory` 新增 `inventory.route.ts`（現有是 sync payload，無 REST read）
- `quotations/:id` 新增 `quotations.route.ts`（現無 read endpoint）
- `sales-orders/:id` 新增 `sales-orders.route.ts`（現無 read endpoint）

### 8.6 Tool caller 問題解析用 regex，不靠 LLM

```python
# packages/ai_service/src/tools/query_parser.py
import re

SKU_PATTERN   = re.compile(r'\b[A-Z]{2,}[-_]?[A-Z0-9]+\b')
NUMERIC_ID    = re.compile(r'#?(\d+)')

def parse_sku(question: str) -> str | None:
    m = SKU_PATTERN.search(question)
    return m.group(0) if m else None

def parse_id(question: str) -> int | None:
    m = NUMERIC_ID.search(question)
    return int(m.group(1)) if m else None
```

找不到參數時，先呼叫 search endpoint，再回「請提供產品型號 / 編號」，不猜測。

### 8.7 Chroma role filter 用 boolean metadata（不用 list contains）

```yaml
# card metadata 範例
entity_type: product
entity_id: 1
role_admin: true
role_sales: true
role_warehouse: true
```

```python
# query filter 範例
{"role_warehouse": True}
```

### 8.8 Flutter SSE parser 必須用 LineSplitter

```dart
// packages/frontend/lib/providers/ai_provider.dart
response.data.stream
  .transform(utf8.decoder)
  .transform(const LineSplitter())   // ← 處理 chunk 邊界，不用 split('\n')
  .listen((line) {
    if (line.startsWith('data: ')) {
      final json = jsonDecode(line.substring(6));
      // 處理 token / source / done
    }
  });
```

### 8.9 SSE event 格式統一用 JSON（不用字串協定）

```
data: {"type":"token","content":"IC-8800"}
data: {"type":"source","endpoint":"/api/v1/inventory","entity":"inventory_items"}
data: {"type":"done"}
```

不使用 `[SOURCE]`、`[DONE]` 字串標記，減少解析歧義。

### 8.10 inventory read endpoint：availableQuantity 計算

```ts
// packages/backend/src/routes/inventory.route.ts
// inventory_items 有 DB CHECK: quantity_on_hand >= 0, quantity_reserved <= quantity_on_hand
const available = item.quantityOnHand - item.quantityReserved;

return {
  productId: item.productId,
  quantityOnHand: item.quantityOnHand,
  quantityReserved: item.quantityReserved,
  availableQuantity: available,              // 主要回答欄位
  minStockLevel: item.minStockLevel,
  alertStockLevel: item.alertStockLevel,
  criticalStockLevel: item.criticalStockLevel,
};
```

### 8.11 customers/search 權限比現有 list endpoint 更嚴格

| Endpoint | 現有規則 | v5.0 規則 |
|---|---|---|
| `GET /api/v1/customers` | 任何已登入角色 | **不動**，避免破壞 Flutter 現有畫面 |
| `GET /api/v1/customers/search` | 新增 | `requireRole(['admin', 'sales'])`，warehouse 403 |
| `GET /api/v1/customers/:id` | 任何已登入角色 | **不動** |

Phase 4 再統一收緊 list endpoint 權限。

### 8.12 AI endpoint rate limit 在 M0.4 就要加

```ts
// packages/backend/src/routes/ai.route.ts
app.post('/chat', {
  preHandler: [app.verifyJwt],
  config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
}, handler);
```

現有全域是 50 req/min，AI endpoint 需獨立收緊到 10 req/min/IP。

### 8.13 Fastify SSE proxy 注意事項

```ts
// proxy 關鍵邏輯
reply.raw.setHeader('Content-Type', 'text/event-stream');
reply.raw.setHeader('Cache-Control', 'no-cache');
reply.raw.setHeader('X-Accel-Buffering', 'no');  // 防止 nginx 緩衝

// upstream 失敗 → 503
// request timeout 60s
// client abort → destroy upstream response
// 結束後一定要 finishAuditLog
```

不使用 Fastify plugin，直接用 `reply.raw`（Node HTTP response）操作 SSE。

---

## 九、開發策略（10 倍效率）

### 9.1 「垂直薄片」優先，不從零做完整系統

先打通一條端到端鏈路：

```
Flutter dummy question
  → Fastify /api/v1/ai/chat（JWT + rate limit + audit pending）
  → ai_service /chat（X-Internal-Token 驗證通過）
  → 回傳固定 SSE token stream
  → Flutter LineSplitter 逐字顯示
  → audit_log finishAuditLog status=success
```

這條通了再疊 RAG / Tool。提早暴露 SSE、proxy、auth、Dio stream 的問題。

### 9.2 Tool MVP 只先做 2 個

1. `get_inventory`
2. `search_products`

驗證完整鏈路（role、tool caller、read endpoint、audit）後再加其他 tool。

### 9.3 先用 deterministic fake LLM

```bash
AI_FAKE_LLM=true
```

fake mode 回固定 token stream，可用於：
- 開發 Fastify proxy
- 開發 Flutter SSE
- 測 audit log
- 跑 CI（不依賴 GPU / Ollama）

### 9.4 Golden questions 最先建立（調整自 V4）

**V4 把 M0.5 放在 M0 最後；v5.0 調整為 M0 最先做**。

哪怕只有 5 題，後面再補。讓 M1 開始就有明確驗收標準。

```
docs/artifacts/phase3-ai-golden-questions.md
```

每題格式：

```markdown
## GQ-001（static）
問題：IC-8800 的最低庫存水位是多少？
預期路由：static
預期來源：RAG / product card
預期 status：success
```

建議題目數量：
- 10 題 static（產品 FAQ、公司資訊）
- 10 題 dynamic（庫存、報價、訂單）
- 10 題 blocked（prompt injection、system prompt、資安攻擊）
- 6 題 role-based（warehouse 問報價 → 403 / 遮罩）

### 9.5 audit service 用 helper，不手寫

```
packages/backend/src/services/audit.service.ts
```

提供：

| 函數 | 用途 |
|---|---|
| `createAuditLog(params)` | 寫入 pending 記錄，回傳 id |
| `finishAuditLog(id, result)` | update status + finishedAt |
| `logAuditEvent(params)` | 寫入 tool_call / blocked 等獨立事件 |
| `hashText(text)` | SHA-256，用於 questionHash |
| `redactText(text)` | 移除 PII pattern（email、電話、身分證） |

### 9.6 backup smoke 先做，不做排程平台

Sprint 0 只做：

- `scripts/backup_pg.ps1` — 手動執行，產生 `.pgdump.gpg`
- `scripts/restore_pg.ps1` — 手動執行，還原到目標 DB
- `docs/phase3-restore-runbook.md` — 步驟文件

排程（Windows Task Scheduler / cron）在 Sprint D 接。

### 9.7 PRD 範例降級為參考

所有 SQL / Drizzle 查詢以 `packages/backend/src/schemas/` 為 source of truth，PRD 範例不可直接複製。

---

## 十、里程碑與任務拆分

### 推薦執行順序（v5.0 調整版）

```text
M0.5 Golden questions（調整為最先）
M0.1 audit_logs schema
M0.2 audit service
M0.4 AI proxy placeholder（含 rate limit）
M1.1 ai_service 套件建立 + fake SSE
M1.2 Fastify SSE proxy（含 X-Internal-Token）
M1.3 Flutter AiProvider LineSplitter parser
M2.1 products/search endpoint
M2.2 inventory read endpoint
M2.3 tool parser（SKU + ID regex）
M2.4 inventory tool caller（帶 JWT）
M2.5 deterministic inventory answer template
M0.3 backup / restore MVP（可並行）
M3   RAG static MVP
M4   AI chat 完整化（query router + Ollama）
M5   擴充 read endpoints + tools
M6   Flutter 完整 Chat UI
M7   部署驗收
```

---

### M0：安全地基

#### M0.5 Golden questions（最優先）

| 項目 | 內容 |
|---|---|
| 目標 | 建立整個 Phase 3 的驗收題庫 |
| 檔案 | `docs/artifacts/phase3-ai-golden-questions.md` |
| 格式 | 每題含：問題、預期路由、預期來源、預期 status |
| 驗收 | static / dynamic / blocked / role-based 各類齊全，至少 36 題 |

#### M0.1 建立 audit_logs schema

| 項目 | 內容 |
|---|---|
| 目標 | 新增 `audit_logs` Drizzle schema + migration |
| 檔案 | `packages/backend/src/schemas/audit_logs.schema.ts`、更新 `index.ts` |
| 欄位 | 見第五節 5.2 |
| 驗收 | `npm run db:generate` 產生 migration；不影響 `processed_operations` 表 |

#### M0.2 建立 audit service

| 項目 | 內容 |
|---|---|
| 目標 | 統一寫入 audit log 的 helper |
| 檔案 | `packages/backend/src/services/audit.service.ts` |
| 輸出 | `createAuditLog`, `finishAuditLog`, `logAuditEvent`, `hashText`, `redactText` |
| 測試 | `audit.service.test.ts`：hash 產生、redact 去 PII、finish 更新狀態 |
| 驗收 | unit test 全過；`processed_operations` 表不被動到 |

#### M0.3 備份腳本 MVP

| 項目 | 內容 |
|---|---|
| 目標 | 可手動產生加密 DB 備份並還原 |
| 檔案 | `scripts/backup_pg.ps1`、`scripts/restore_pg.ps1`、`docs/phase3-restore-runbook.md` |
| 輸入 | `DATABASE_URL`, `BACKUP_PASSPHRASE`, `BACKUP_DIR` |
| 輸出 | `<timestamp>.pgdump.gpg` |
| 驗收 | 在測試 DB 備份→清空→還原→資料一致 |

#### M0.4 AI proxy placeholder

| 項目 | 內容 |
|---|---|
| 目標 | `/api/v1/ai/chat` 需要 JWT，先回 501；建立 rate limit |
| 檔案 | `packages/backend/src/routes/ai.route.ts`、`app.ts` |
| Rate limit | 10 req/min/IP（獨立於全域 50 req/min） |
| 驗收 | 未登入 → 401；登入後 → 501；audit log 記 `pending/error` |

Route 寫法：

```ts
// app.ts
app.register(aiRoutes, { prefix: '/api/v1/ai' });

// ai.route.ts
app.post('/chat', {
  preHandler: [app.verifyJwt],
  config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
}, handler);
```

---

### M1：端到端 SSE 薄片

#### M1.1 ai_service 套件建立 + fake SSE

| 項目 | 內容 |
|---|---|
| 目標 | 建立 ai_service 套件結構；`/chat` 可驗 internal token 並回 SSE |
| 檔案 | 見第三節 3.2 完整目錄 |
| 驗收 | curl 帶正確 `X-Internal-Token` 可收到 `data:` chunks 與 `data: {"type":"done"}`；錯誤 token → 403 |
| 同步 | 更新 `.env.production.example` 加入所有 ai_service 新變數 |

#### M1.2 Fastify SSE proxy

| 項目 | 內容 |
|---|---|
| 目標 | `/api/v1/ai/chat` 轉發 ai_service SSE，帶 `X-Internal-Token` + 使用者 JWT |
| 檔案 | `packages/backend/src/routes/ai.route.ts` |
| 驗收 | 帶 JWT 呼叫 Fastify 可收到 ai_service chunks；upstream 失敗 → 503；60s timeout；client abort 可中止 upstream；audit log 最終有 status |

#### M1.3 Flutter AiProvider LineSplitter parser

| 項目 | 內容 |
|---|---|
| 目標 | Flutter 顯示串流文字，chunk 邊界不破壞解析 |
| 檔案 | `packages/frontend/lib/providers/ai_provider.dart` |
| 驗收 | 刻意截斷 chunk 仍可正確顯示；error state 可顯示錯誤訊息 |

---

### M2：第一個動態 Tool：庫存

#### M2.1 Product search endpoint

| 項目 | 內容 |
|---|---|
| 目標 | 用 SKU / name 搜產品，加在現有 route file |
| 檔案 | `packages/backend/src/routes/products.route.ts` |
| Endpoint | `GET /api/v1/products/search?q=<string>` |
| 回傳 | id, name, sku, unitPrice, minStockLevel |
| 權限 | admin / sales / warehouse |
| 驗收 | SKU 精準命中；deleted 產品不回傳；空 q → 422 |

#### M2.2 Inventory read endpoint

| 項目 | 內容 |
|---|---|
| 目標 | 查產品庫存 |
| 檔案 | `packages/backend/src/routes/inventory.route.ts`、更新 `app.ts` |
| Endpoint | `GET /api/v1/inventory?productId=<number>` |
| 回傳 | `quantityOnHand`, `quantityReserved`, `availableQuantity`, stock levels |
| 計算 | `availableQuantity = quantityOnHand - quantityReserved` |
| 權限 | admin / sales / warehouse |
| 驗收 | deleted 產品 → 404；inventory 不存在 → 404；計算正確 |

#### M2.3 Tool parser

| 項目 | 內容 |
|---|---|
| 目標 | 從問題抽 SKU / productId |
| 檔案 | `packages/ai_service/src/tools/query_parser.py` |
| 驗收 | `IC-8800 現在庫存多少` → `IC-8800`；`#123 的庫存` → `123`；找不到 → None |
| 測試 | `test_query_parser.py`：至少 10 個測試案例 |

#### M2.4 Inventory tool caller

| 項目 | 內容 |
|---|---|
| 目標 | ai_service 帶使用者 JWT 呼叫 Fastify，查庫存 |
| 檔案 | `packages/ai_service/src/tools/erp_tools.py` |
| 流程 | parse_sku → /products/search → /inventory?productId=... |
| 驗收 | warehouse / sales / admin 都能查；無 JWT → 401 被捕捉並回 error |

#### M2.5 Deterministic inventory answer template

| 項目 | 內容 |
|---|---|
| 目標 | 不靠 LLM 也能回庫存答案，確保資料正確性 |
| 檔案 | `packages/ai_service/src/tools/formatters.py` |
| 驗收 | 回答包含現有庫存、已預留、可用量、資料來源 endpoint |

---

### M3：RAG static MVP

#### M3.1 Schema mapping

| 項目 | 內容 |
|---|---|
| 目標 | 定義卡片欄位，對照現有 Drizzle schema |
| 檔案 | `packages/ai_service/src/indexing/schema_mapping.md` |
| 驗收 | 不使用不存在欄位；每個 entity 的可用欄位清單齊全 |

#### M3.2 Product cards

欄位：`id`, `name`, `sku`, `unit_price`, `min_stock_level`

```yaml
entity_type: product
entity_id: 1
role_admin: true
role_sales: true
role_warehouse: true
source: db
```

#### M3.3 Customer cards

欄位：`id`, `name`，`contact` 可選

敏感欄位（`email`, `tax_id`）**不進卡片**。

```yaml
entity_type: customer
entity_id: 5
role_admin: true
role_sales: true
role_warehouse: false    ← warehouse 查不到
source: db
```

#### M3.4 Chroma build index

| 項目 | 內容 |
|---|---|
| 目標 | 建立 ChromaDB index，支援重建 |
| 檔案 | `packages/ai_service/src/indexing/build_index.py` |
| 驗收 | 可重建；metadata filter 生效；warehouse 查不到 customer card |

#### M3.5 Hybrid retriever

| 項目 | 內容 |
|---|---|
| 目標 | Vector + BM25 |
| 檔案 | `packages/ai_service/src/rag/retriever.py` |
| 驗收 | SKU 精準命中；role filter 通過 golden questions role-based 題 |

---

### M4：AI chat 完整化

#### M4.1 Query router

| 項目 | 內容 |
|---|---|
| 目標 | static / dynamic / blocked 分類 |
| 檔案 | `packages/ai_service/src/router/query_router.py` |
| 驗收 | golden questions 36 題：blocked 分類正確率 100%；static/dynamic > 90% |

#### M4.2 Prompt policy

| 項目 | 內容 |
|---|---|
| 目標 | 防幻覺、防注入 |
| 檔案 | `packages/ai_service/src/rag/prompt.py` |
| 驗收 | 無 context 時不編造答案；要求揭露 system prompt → blocked |

#### M4.3 Ollama client

| 項目 | 內容 |
|---|---|
| 目標 | 支援 fake mode 與 real mode |
| 檔案 | `packages/ai_service/src/llm/ollama_client.py` |
| 驗收 | `AI_FAKE_LLM=true` 無需 Ollama 可完成整個流程；real mode 可串流 |

#### M4.4 Source events

```
event: source
data: {"type":"source","endpoint":"/api/v1/inventory","entityType":"inventory_items","entityId":"123"}
```

---

### M5：擴充 read endpoints 與 tools

#### M5.1 Customer search / read

| Endpoint | 檔案 | 權限 |
|---|---|---|
| `GET /api/v1/customers/search?q=...` | 加在 `customers.route.ts` | admin / sales（warehouse 403）|
| `GET /api/v1/customers/:id` | 現有，**不動** | 保持現狀 |

#### M5.2 Quotation read

| Endpoint | 檔案 | 權限 |
|---|---|---|
| `GET /api/v1/quotations/:id` | 新增 `quotations.route.ts` | admin / sales（warehouse 403）|

需 join `order_items` 回明細；deleted rows 不回傳。

#### M5.3 Sales order read

| Endpoint | 檔案 | 權限 |
|---|---|---|
| `GET /api/v1/sales-orders/:id` | 新增 `sales-orders.route.ts` | admin / sales / warehouse |

warehouse 可看數量，不回傳金額（`unit_price`, `total_amount` 欄位遮罩）。

#### M5.4 Tool audit

每次 tool call 寫一筆 `ai.tool_call` 事件：

```ts
await logAuditEvent({
  requestId,           // 與 ai.chat 相同
  userId, userRole,
  action: 'ai.tool_call',
  toolName: 'get_inventory',
  resourceType: 'inventory',
  resourceId: String(productId),
  status: 'success',   // success | denied | error
});
```

---

### M6：Flutter 完整 Chat UI

#### M6.1 ChatScreen

| 項目 | 內容 |
|---|---|
| 目標 | 輸入、送出、串流回答 |
| 檔案 | `packages/frontend/lib/features/ai/chat_screen.dart` |
| 驗收 | loading / error / retry / cancel 都可用；網路斷線有 error UI |

#### M6.2 SourceCard

| 項目 | 內容 |
|---|---|
| 目標 | 顯示 RAG doc id 或 endpoint 來源 |
| 檔案 | `packages/frontend/lib/features/ai/source_card.dart` |
| 驗收 | 可展開；文字不溢出；dynamic source 顯示 endpoint 名稱 |

#### M6.3 Home entry

| 項目 | 內容 |
|---|---|
| 目標 | HomeScreen AppBar / menu 加 AI 助理入口 |
| 檔案 | `packages/frontend/lib/main.dart` |
| 驗收 | 登入後可進入；登出後不可用 |

---

### M7：部署與驗收

#### M7.1 Docker prod integration

| 項目 | 內容 |
|---|---|
| 目標 | ai_service internal only，加入 prod compose |
| 檔案 | `docker-compose.prod.yml`、`.env.production.example` |
| 驗收 | 只有 backend port 對外；ai_service 無 ports；chroma_data volume 持久化 |

#### M7.2 Restore drill

```
空 DB → scripts/restore_pg.ps1 → db:migrate → login → sync pull → 成功
```

#### M7.3 Security tests

| 測試 | 預期 |
|---|---|
| prompt injection 10 題（golden questions blocked 類）| 全部 blocked |
| warehouse 問報價 | 403 或欄位遮罩 |
| 直接打 ai_service port（若意外暴露）| 無法連線 |
| 每分鐘超過 10 次 AI 請求 | 429 |
| 錯誤 X-Internal-Token | 403 |
| AI service 停止 | ERP login / sync 正常運作 |

#### M7.4 Performance tests

| 指標 | 目標 |
|---|---|
| 50 次連續問答 | 不崩潰 |
| TTFT P50 | < 2s |
| TTFT P95 | < 5s |
| VRAM | < 5.5GB |

---

## 十一、最小可合併 PR 切法（v5.0 更新版）

### PR-1：Audit Foundation

- `audit_logs` schema + migration
- audit service（`createAuditLog`, `finishAuditLog`, `logAuditEvent`, `hashText`, `redactText`）
- unit tests
- **不動** `processed_operations` 表

### PR-2：AI Proxy Placeholder

- `ai.route.ts`（`/chat` 回 501）
- JWT required
- rate limit 10 req/min
- audit pending/error
- `.env.production.example` 加 `AI_SERVICE_URL`, `AI_SERVICE_INTERNAL_TOKEN`

### PR-3：Fake SSE End-to-End

- `packages/ai_service/` 完整套件建立（Dockerfile, requirements.txt, 目錄結構）
- ai_service `POST /chat`（驗 X-Internal-Token，回 fake SSE JSON events）
- Fastify SSE proxy（轉發 userJwt + X-Internal-Token）
- Flutter AiProvider LineSplitter parser
- `docker-compose.prod.yml` 加 ai_service service

### PR-4：Inventory Tool Slice

- `GET /api/v1/products/search`（加在 `products.route.ts`）
- `GET /api/v1/inventory`（新增 `inventory.route.ts`）
- `query_parser.py`（SKU + ID regex，含測試）
- `erp_tools.py`（tool caller，帶 JWT）
- `formatters.py`（deterministic inventory answer）
- schema_mapping.md

### PR-5：Backup / Restore MVP

- `scripts/backup_pg.ps1`
- `scripts/restore_pg.ps1`
- `docs/phase3-restore-runbook.md`
- smoke test 筆記

### PR-6：RAG Static MVP

- card_generator.py（使用真實 schema 欄位，read-only DB user）
- build_index.py（支援重建）
- hybrid retriever
- role filter tests（warehouse 查不到 customer card）

### PR-7：Ollama Integration

- query router
- prompt policy
- ollama_client.py（fake / real mode）
- golden question eval（36 題 pass rate 記錄）

### PR-8：Remaining Tools

- `customers/search`（加在 `customers.route.ts`，warehouse 403）
- `quotations/:id`（新增 route file）
- `sales-orders/:id`（新增 route file，warehouse 遮罩金額）
- tool caller 擴充
- tool audit 事件

### PR-9：Chat UI

- ChatScreen
- SourceCard
- Home entry

### PR-10：Production Hardening

- docker prod 驗證
- WAF 更新
- restore drill 記錄
- 壓測結果
- 資安測試結果

---

## 十二、測試策略（v5.0 新增）

### 12.1 各 PR 最低測試需求

| PR | 最低測試需求 |
|---|---|
| PR-1 | audit.service.test.ts：hash、redact、createAuditLog、finishAuditLog |
| PR-3 | 手動 curl 驗證 SSE 可收 + chunk 截斷模擬 |
| PR-4 | test_query_parser.py：≥10 案例；inventory endpoint integration test |
| PR-6 | role filter test：warehouse 查不到 customer card、admin 可查所有 |
| PR-7 | golden questions eval script：36 題 pass rate 輸出到 stdout |
| PR-8 | customer search 403 test（warehouse token）；quotation amount masking test |

### 12.2 fake LLM 在 CI 的用途

CI pipeline 應設定：

```yaml
env:
  AI_FAKE_LLM: "true"
```

這樣 PR-3 之後的所有 CI run 不依賴 Ollama，可完整跑完 audit、proxy、Flutter parser 的測試。

---

## 十三、V5.0 驗收矩陣

| 類別 | 必過項目 |
|---|---|
| 套件結構 | ai_service 依第三節目錄建立；Dockerfile 可 build |
| 服務間通訊 | X-Internal-Token 驗證；ai_service 無直連 DB；userJwt 正確轉發 |
| 備份 | 可產生加密備份；可還原到空 DB；smoke test 成功 |
| Audit 邊界 | processed_operations 不被動到；audit_logs 有 pending/success/blocked/error |
| Rate limit | AI endpoint 10 req/min 獨立生效 |
| 權限 | warehouse 無法看 customer sensitive / quotation amount |
| SSE 正確性 | chunk split 不破壞 Flutter parser；client cancel 可中止 upstream |
| Tool 資料 | inventory tool 不靠模型猜數字；availableQuantity 計算正確 |
| RAG | role metadata boolean filter 生效；warehouse 查不到 customer card |
| 穩定 | AI service down 不影響 login / sync |
| 效能 | 50 次問答不崩潰；VRAM < 5.5GB |
| Golden questions | 36 題分類 blocked 100%；static/dynamic > 90% |

---

## 十四、結論

v5.0 在 V4_codex 的基礎上補上了六個開發前必須決定的架構缺口：

1. **ai_service 套件結構**：定義目錄、Dockerfile、docker-compose 配置，M1.1 有具體起點
2. **JWT 轉發機制**：Flutter → Fastify → ai_service → Fastify 的 token 流全部說清楚
3. **X-Internal-Token**：ai_service 不對外暴露，但也需要驗身份
4. **audit_logs 邊界**：與 processed_operations 不混用，各司其職
5. **完整 env vars**：10 個新變數，含說明與預設值
6. **測試策略**：每個 PR 的最低測試需求，CI 用 fake LLM

**建議起點**：

```
M0.5 Golden questions（先寫 10 題，後面補）
  → PR-1 Audit Foundation
  → PR-2 AI Proxy Placeholder
  → PR-3 Fake SSE End-to-End（整個鏈路第一次打通）
  → PR-4 Inventory Tool Slice（動態查詢第一次可用）
```

完成 PR-4 即代表系統的核心價值（手機問庫存、有 audit、有權限邊界）已可演示，後續 PR-5 到 PR-10 均為功能擴充，不影響核心架構的穩定性。
