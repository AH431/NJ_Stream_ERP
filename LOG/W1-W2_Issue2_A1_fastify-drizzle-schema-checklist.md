# W1–W2 / Issue #2 — Agent A-1：Fastify 專案 + Drizzle Schema 完成記錄

**Issue**：[#2 Agent A-1: 初始化 Fastify 專案 + Drizzle Schema (全 8 表)](https://github.com/AH431/NJ_Stream_ERP/issues/2)  
**Milestone**：W1–W2 Foundation  
**完成日期**：2026-04-10  
**最終狀態**：✅ 專業級驗收通過 — 待 Docker 啟動後執行 `db:push` + `db:studio`

---

## 1. 最終產出檔案清單

| 檔案 | 說明 | 狀態 |
|------|------|------|
| `packages/backend/tsconfig.json` | `allowImportingTsExtensions + noEmit`（drizzle-kit 相容） | ✅ |
| `packages/backend/drizzle.config.ts` | schema glob `*.schema.ts`（避免 CJS 解析 .js 問題） | ✅ |
| `packages/backend/.env` | 開發環境變數（不提交 Git） | ✅ |
| `packages/backend/.env.example` | 環境變數範本 | ✅ |
| `packages/backend/src/constants/index.ts` | `SYNC.BATCH_LIMIT=50`、`SYNC.CLEANUP_DAYS=30` 命名空間 + 全常數 | ✅ |
| `packages/backend/src/plugins/db.ts` | Drizzle + postgres.js 連線插件 | ✅ |
| `packages/backend/src/schemas/index.ts` | 全 8 表匯出 + 集中定義所有 Relations | ✅ |
| `packages/backend/src/schemas/users.schema.ts` | role enum、`$onUpdate`、`mode:'date'` | ✅ |
| `packages/backend/src/schemas/customers.schema.ts` | 軟刪除 deletedAt、LWW updatedAt | ✅ |
| `packages/backend/src/schemas/products.schema.ts` | sku UNIQUE、numeric(12,2) | ✅ |
| `packages/backend/src/schemas/quotations.schema.ts` | `convertedToOrderId`（First-to-Sync wins）、移除 JSONB items | ✅ |
| `packages/backend/src/schemas/sales_orders.schema.ts` | quotationId FK（First-to-Sync wins）、status enum | ✅ |
| `packages/backend/src/schemas/order_items.schema.ts` | 正規化明細表（替代 JSONB）、3 個索引 | ✅ |
| `packages/backend/src/schemas/inventory_items.schema.ts` | DB CHECK 約束、warehouseId 保留無 FK | ✅ |
| `packages/backend/src/schemas/processed_operations.schema.ts` | UNIQUE(operation_id)、`idx_processed_at`、`idx_entity_type` | ✅ |
| `packages/backend/src/app.ts` | Fastify buildApp()（cors、helmet、db plugin） | ✅ |
| `packages/backend/src/index.ts` | 伺服器入口 | ✅ |
| `packages/backend/src/types/index.ts` | Sync 型別 + ServerState discriminated union | ✅ |
| `packages/backend/src/types/payloads.ts` | 各 entity Payload 型別（對應 API Contract v1.6） | ✅ |

---

## 2. 全 8 張 Schema 最終對照

| # | 表名 | 關鍵設計 | `db:generate` 驗證 |
|---|------|---------|-------------------|
| 1 | `users` | role enum、UNIQUE(username, email)、`$onUpdate` | ✅ 9 cols |
| 2 | `customers` | 軟刪除 deletedAt、LWW updatedAt | ✅ 7 cols |
| 3 | `products` | UNIQUE(sku)、numeric(12,2) | ✅ 8 cols |
| 4 | `quotations` | `convertedToOrderId`（First-to-Sync wins）、正規化（無 JSONB） | ✅ 10 cols 2 fks |
| 5 | `sales_orders` | quotationId FK、status enum | ✅ 10 cols 3 fks |
| 6 | `order_items` | 正規化明細、numeric(12,2)、3 索引 3 fks | ✅ 9 cols 3 idx |
| 7 | `inventory_items` | CHECK(on_hand>=0)、CHECK(reserved<=on_hand)、1 索引 | ✅ 9 cols 1 idx |
| 8 | `processed_operations` | UNIQUE(operation_id)、`idx_processed_at`、`idx_entity_type` | ✅ 11 cols 2 idx |

---

## 3. 同步協定 v1.6 設計對照

| 規則 | 實作位置 | 狀態 |
|------|---------|------|
| `SYNC.BATCH_LIMIT = 50` | `constants/index.ts` SYNC 命名空間 | ✅ |
| `SYNC.CLEANUP_DAYS = 30` | `constants/index.ts` SYNC 命名空間 | ✅ |
| DELTA_UPDATE 四種 type 常數 | `constants/index.ts` DELTA_TYPES | ✅ |
| 錯誤碼常數（INSUFFICIENT_STOCK 等） | `constants/index.ts` SYNC_ERROR_CODES | ✅ |
| 庫存 DB 層約束（on_hand>=0、reserved<=on_hand） | `inventory_items.schema.ts` CHECK constraints | ✅ |
| 冪等去重 | `processed_operations.schema.ts` UNIQUE(operation_id) | ✅ |
| 清理索引支援（30 天排程） | `idx_processed_at` on processedAt | ✅ |
| First-to-Sync wins | `quotations.convertedToOrderId`、`sales_orders.quotationId` FK | ✅ |
| 軟刪除（禁止 Hard Delete） | 全部業務表含 deletedAt（mode:'date'） | ✅ |
| ServerState discriminated union | `types/payloads.ts` + `types/index.ts` | ✅ |
| order_items 正規化（非 JSONB） | 獨立 `order_items` 表取代 quotations.items JSONB | ✅ |
| Relations 集中定義（無循環引用） | `schemas/index.ts` | ✅ |

---

## 4. 驗收指令執行結果

| 指令 | 結果 | 備註 |
|------|------|------|
| `docker ps \| grep nj-erp-postgres` | ⚠️ 待執行 | Docker CLI 未在 bash PATH，需 Windows 終端 |
| `npm install` | ✅ node_modules OK | fastify-plugin 已透過 peerDep 引入 |
| `npx tsc --noEmit` | ✅ **零錯誤** | 加入 `allowImportingTsExtensions: true` 後通過 |
| `npm run db:generate` | ✅ **全 8 表 SQL 正確產出** | 含 CHECK、UNIQUE、5 個索引 |
| `npm run db:push` | ⚠️ 待執行 | 需 Docker 運行 |
| `npm run db:studio` | ⚠️ 待執行 | W1 Gate 最終目視確認 |

---

## 5. 問題診斷與修正記錄

| 問題 | 原因 | 修正方式 | Commit |
|------|------|---------|--------|
| `db:generate` 報 MODULE_NOT_FOUND `.schema.js` | drizzle-kit 用 CJS require 無法解析 ESM `.js` → `.ts` | schema 相對引入改為 `.ts` 擴充名 | `1c89b9b` |
| `tsc --noEmit` 報 TS5097 | `.ts` 擴充名引入需 `allowImportingTsExtensions` | tsconfig 加入 `allowImportingTsExtensions: true` + `noEmit: true` | `1c89b9b` |
| 第 8 表為 `warehouses`（錯誤） | 初版設計誤加倉庫表 | 刪除 `warehouses.schema.ts`，新增 `order_items.schema.ts`（正規化設計） | `ea355f5` |
| `quotations` 使用 JSONB `items` | 違反正規化設計原則 | 移除 JSONB，明細改存於 `order_items` | `ea355f5` |
| timestamp 缺少 `{ mode: 'date' }` | 初版遺漏 | 全部 timestamp 補上 mode:'date' | `ea355f5` |
| `updatedAt` 缺少 `$onUpdate` | 初版遺漏 | 全部 updatedAt 補上 `.$onUpdate(() => new Date())` | `ea355f5` |
| `processed_operations` 缺索引 | 初版未加 | 新增 `idx_processed_at`、`idx_entity_type` | `ea355f5` |

---

## 6. W1 Gate 最終驗收步驟

```bash
# Windows 終端執行
docker compose up -d
docker ps   # 確認 nj-erp-postgres STATUS = healthy

# 推送 Schema 至 PostgreSQL
cd packages/backend
npm run db:push

# Drizzle Studio 目視驗證（W1 Gate 驗收條件）
npm run db:studio
# 瀏覽器開啟 https://local.drizzle.studio
# 驗收清單：
#   ✅ 全 8 張表可見
#   ✅ inventory_items 顯示 CHECK constraints
#   ✅ processed_operations 顯示 uq_operation_id UNIQUE
#   ✅ order_items 顯示 3 個 FK
```

**W1 Gate 驗收標準達成 → Issue #2 可關閉**

---

## 7. 後續 TODO

| 項目 | 說明 | 處理時機 |
|------|------|---------|
| `fastify-plugin` 加入 package.json | 目前透過 peerDep 引入，建議明確宣告 | W1–W2 |
| Auth 路由實作 | `app.ts` 預留 `authRoutes` TODO | Issue #21（W1–W2） |
| Sync Push 路由實作 | `app.ts` 預留 `syncRoutes` TODO | W3 前 |
| `drizzle/meta/` gitignore 策略確認 | 是否保留 migration 歷史 | W3 討論 |
