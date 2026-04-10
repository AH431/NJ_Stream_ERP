# W1–W2 / Issue #2 — Agent A-1：Fastify 專案 + Drizzle Schema 完成記錄

**Issue**：[#2 Agent A-1: 初始化 Fastify 專案 + Drizzle Schema (全 8 表)](https://github.com/AH431/NJ_Stream_ERP/issues/2)  
**Milestone**：W1–W2 Foundation  
**完成日期**：2026-04-10  
**狀態**：✅ 檔案產出完成 — 待 Docker 啟動後執行 W1 Gate 驗收

---

## 1. 產出檔案清單

| 檔案 | 說明 | 狀態 |
|------|------|------|
| `packages/backend/tsconfig.json` | TypeScript 設定（ESNext、paths alias `@/*`） | ✅ |
| `packages/backend/drizzle.config.ts` | Drizzle Kit 設定（schema entry、out dir） | ✅ |
| `packages/backend/.env` | 開發環境變數（DATABASE_URL、JWT_SECRET 等） | ✅ |
| `packages/backend/.env.example` | 環境變數範本（可提交 Git） | ✅ |
| `packages/backend/src/constants/index.ts` | 同步協定常數（DELTA_TYPES、錯誤碼、角色等） | ✅ |
| `packages/backend/src/plugins/db.ts` | Drizzle + postgres.js 連線插件 | ✅ |
| `packages/backend/src/schemas/index.ts` | Schema 統一匯出 entry point | ✅ |
| `packages/backend/src/schemas/users.schema.ts` | 使用者表 | ✅ |
| `packages/backend/src/schemas/warehouses.schema.ts` | 倉庫表（第 8 張，MVP id=1） | ✅ |
| `packages/backend/src/schemas/customers.schema.ts` | 客戶表 | ✅ |
| `packages/backend/src/schemas/products.schema.ts` | 產品表 | ✅ |
| `packages/backend/src/schemas/quotations.schema.ts` | 報價表（含 First-to-Sync wins 欄位） | ✅ |
| `packages/backend/src/schemas/sales_orders.schema.ts` | 訂單表 | ✅ |
| `packages/backend/src/schemas/inventory_items.schema.ts` | 庫存表（含 DB CHECK 約束） | ✅ |
| `packages/backend/src/schemas/processed_operations.schema.ts` | 已處理操作表（冪等去重 UNIQUE） | ✅ |
| `packages/backend/src/app.ts` | Fastify buildApp()（cors、helmet、db plugin） | ✅ |
| `packages/backend/src/index.ts` | 伺服器入口 | ✅ |
| `packages/backend/src/types/index.ts` | Sync 相關 TypeScript 型別 | ✅ |
| `packages/backend/src/types/payloads.ts` | ServerState discriminated union Payload 型別 | ✅ |
| `.gitignore` | 補充 node_modules、.env、dist、drizzle/meta 排除 | ✅ |
| `node_modules/`（npm install） | 依賴安裝完成 | ✅ |

---

## 2. 全 8 張 Schema 對照 ERD

| # | 表名 | Schema 檔案 | 同步協定關鍵設計 | 狀態 |
|---|------|------------|----------------|------|
| 1 | `users` | `users.schema.ts` | role enum（sales/warehouse/admin） | ✅ |
| 2 | `warehouses` | `warehouses.schema.ts` | MVP isDefault=true（id=1），欄位保留供未來擴充 | ✅ |
| 3 | `customers` | `customers.schema.ts` | 軟刪除 deletedAt，LWW updatedAt | ✅ |
| 4 | `products` | `products.schema.ts` | unitPrice numeric(12,2)，sku UNIQUE | ✅ |
| 5 | `quotations` | `quotations.schema.ts` | convertedToOrderId（First-to-Sync wins 去重欄位） | ✅ |
| 6 | `sales_orders` | `sales_orders.schema.ts` | quotationId FK（First-to-Sync wins），status enum | ✅ |
| 7 | `inventory_items` | `inventory_items.schema.ts` | DB CHECK：on_hand>=0、reserved<=on_hand | ✅ |
| 8 | `processed_operations` | `processed_operations.schema.ts` | operationId UNIQUE（冪等去重） | ✅ |

---

## 3. 同步協定 v1.6 設計對照

| 規則 | 實作位置 | 狀態 |
|------|---------|------|
| DELTA_UPDATE 四種 type 常數 | `constants/index.ts` DELTA_TYPES | ✅ |
| 錯誤碼常數（INSUFFICIENT_STOCK 等） | `constants/index.ts` SYNC_ERROR_CODES | ✅ |
| 庫存約束（on_hand>=0、reserved<=on_hand） | `inventory_items.schema.ts` CHECK constraints | ✅ |
| 冪等去重 | `processed_operations.schema.ts` UNIQUE on operationId | ✅ |
| First-to-Sync wins | `quotations.schema.ts` convertedToOrderId、`sales_orders.schema.ts` quotationId | ✅ |
| 軟刪除（禁止 Hard Delete） | 全部 7 個業務表均含 deletedAt 欄位 | ✅ |
| PROCESSED_OPS_RETENTION_DAYS = 30 | `constants/index.ts` | ✅ |
| MVP 單一倉庫（DEFAULT_WAREHOUSE_ID=1） | `constants/index.ts`、`inventory_items.schema.ts` default(1) | ✅ |
| ServerState discriminated union | `types/payloads.ts` + `types/index.ts` | ✅ |

---

## 4. W1 Gate 驗收步驟（待執行）

```bash
# Step 1：啟動 PostgreSQL（需先開啟 Docker Desktop）
docker compose up -d

# Step 2：等待 healthcheck 通過
docker ps  # 確認 nj-erp-postgres STATUS = healthy

# Step 3：推送 Schema 至資料庫
cd packages/backend
npx drizzle-kit push

# Step 4：Drizzle Studio 可視化驗證（W1 Gate 驗收條件）
npx drizzle-kit studio
# 瀏覽器開啟 https://local.drizzle.studio
# 確認全 8 張表皆可見，inventory_items 的 CHECK constraints 存在
```

**W1 Gate 驗收標準**：Drizzle Studio 可視化所有 8 張表 → Issue #2 可關閉

---

## 5. 已知限制與後續 TODO

| 項目 | 說明 | 預計處理時機 |
|------|------|------------|
| Docker 需手動啟動 | Docker CLI 未在 bash PATH，需在 Windows 終端執行 `docker compose up -d` | 立即（執行 drizzle-kit push 前） |
| `fastify-plugin` 未列於 package.json dependencies | `db.ts` 用到但 package.json 未宣告，透過 fastify 的 peerDep 引入，建議明確加入 | W1–W2 |
| Auth 路由尚未掛載 | `app.ts` 中已預留 `app.register(authRoutes)` 的 TODO 註解 | Issue #21（W1–W2） |
| Sync Push 路由尚未實作 | `app.ts` 中已預留 `app.register(syncRoutes)` 的 TODO 註解 | W3 前 |
| `drizzle/meta/` 已加入 gitignore | 避免 generated migration metadata 提交，需確認團隊是否要保留 migration 歷史 | W3 討論 |
