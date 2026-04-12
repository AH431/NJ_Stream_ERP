# Issue #7 Task List — W3–W4 後端收尾：First-to-Sync Wins + Pull 補完

**Milestone**：W3–W4 CRUD  
**Agent**：A（後端）  
**前置 Issue**：#4（客戶/產品 REST API）、#5（sync/push）均已完成  
**對應 TODO**：`sync.service.ts:554` `// TODO Issue #7：First-to-Sync wins 並發控制`

---

## 背景

Issue #4 已實作客戶/產品 CRUD API（原本是 #7 的 TASKS.md 描述）。  
目前 `processSalesOrder` create 缺少報價轉訂單的並發保護，  
且 `GET /api/v1/sync/pull` 的 `quotations`、`salesOrders` 固定回傳空陣列。  
本 Issue 補齊這兩個缺口。

---

## Phase 1：First-to-Sync wins — `sync.service.ts`

**檔案**：`packages/backend/src/services/sync.service.ts`  
**位置**：`processSalesOrder` → `operationType === 'create'`（第 546–558 行）

### 目標行為

| 情境 | 預期結果 |
|------|---------|
| `quotationId == null`（直接建單） | 直接 insert，不需額外檢查 |
| `quotationId != null` 且報價尚未轉單 | insert salesOrder + 更新 quotation（同一 transaction）|
| `quotationId != null` 且報價已有 `convertedToOrderId` | `FORBIDDEN_OPERATION` + server_state（quotation 目前狀態） |

### 修改步驟

- [x] 若 `quotationId != null`，在 insert 前查詢 `quotations`（`SELECT … WHERE id = quotationId`）
- [x] 若 `quotation` 不存在 → `DATA_CONFLICT`（`找不到 quotationId=X 的報價`）
- [x] 若 `quotation.convertedToOrderId != null` → `FORBIDDEN_OPERATION` + server_state（回傳 quotation 目前狀態，讓前端 Force Overwrite 本地報價）
- [x] 通過檢查後：`tx.insert(salesOrders).returning()` 取得新 order.id
- [x] 同一 transaction 內：`tx.update(quotations).set({ convertedToOrderId: newOrder.id, status: 'converted', updatedAt: new Date() })`
- [x] 移除原本的 `// TODO Issue #7` 註解

### server_state 格式（FORBIDDEN_OPERATION 時）

回傳 `QuotationPayload`，令前端 Force Overwrite 本地報價的 `convertedToOrderId` 與 `status`。  
（items 不含，前端靠 Pull 取得，與 `processQuotation` update LWW 的做法一致。）

---

## Phase 2：GET /api/v1/sync/pull 補完 — `sync.route.ts`

**檔案**：`packages/backend/src/routes/sync.route.ts`  
**位置**：`GET /pull` handler（第 160–221 行）

目前只有 `customer` / `product` 有增量查詢，其餘回傳 `[]`。

### 修改步驟

- [x] import `quotations` from `@/schemas/quotations.schema.js`
- [x] import `salesOrders` from `@/schemas/sales_orders.schema.js`
- [x] `quotations` 查詢：`WHERE updated_at > sinceDate`，回傳格式對齊 `QuotationPayload`（不含 items，items 需另外查 order_items — Phase 2+ 延伸，本 Issue 先回傳主表欄位）
- [x] `sales_orders` 查詢：`WHERE updated_at > sinceDate`，回傳格式對齊 `SalesOrderPayload`
- [x] 移除 `// 只實作 W2 所涵蓋的 customer 與 product，未來 W5 補齊其他` 的佔位符號說明

> **注意**：quotation items（order_items）的增量同步留給 W5 Issue #10（報價 UI），  
> 本 Issue 只補主表增量，防止 pull 永遠回傳空陣列。

---

## Phase 3：API Contract 更新 — `api-contract-sync-v1.6.yaml`

**檔案**：`docs/api-contract-sync-v1.6.yaml`

- [x] 在 `GET /api/v1/sync/pull` response schema 補上 `quotations` 與 `salesOrders` 陣列定義
  （schema 已在 YAML 中定義；更新 description 移除「預留端點 — W6 實作」說明）
- [x] `quotations` 欄位：`id, customerId, createdBy, totalAmount, taxAmount, status, convertedToOrderId, createdAt, updatedAt, deletedAt`
- [x] `salesOrders` 欄位：`id, quotationId, customerId, createdBy, status, confirmedAt, shippedAt, createdAt, updatedAt, deletedAt`

---

## Phase 4：驗收測試（curl）

- [x] **First-to-Sync wins 正向**：  
  裝置 A Push `sales_order:create` with `quotationId=1` → `succeeded`  
  quotation 更新：`status: "converted"`, `convertedToOrderId: 1` ✅

- [x] **First-to-Sync wins 反向**（第二台裝置）：  
  裝置 B 同一 `quotationId=1` 再 Push → `failed[0].code = FORBIDDEN_OPERATION`  
  `server_state.status = "converted"`, `server_state.convertedToOrderId = 1` ✅

- [x] **直接建單（quotationId=null）不受影響**：  
  Push `sales_order:create` without `quotationId` → `succeeded` ✅

- [x] **Pull quotations/sales_orders**：  
  `entityTypes=quotation,sales_order` → 兩類非空（quotation × 1, salesOrders × 2）  
  `entityTypes=customer,product` → quotations/salesOrders 空（篩選正確）✅

- [x] `npm run build` 通過（TypeScript 無型別錯誤）

---

## 驗收自證（sync_logic_check template）

關閉本 Issue 前需依 `.github/ISSUE_TEMPLATE/sync_logic_check.md` 自證：
- First-to-Sync wins 防護是否正確對應同步協定 v1.6 §5（First-to-Sync Wins）
- Pull 補完是否維持 `updated_at > since` 增量語意
