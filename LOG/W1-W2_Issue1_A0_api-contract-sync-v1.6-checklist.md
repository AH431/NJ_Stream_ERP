# W1–W2 / Issue #1 — Agent A-0：Sync API Spec 對照檢查清單

**Issue**：[#1 Agent A-0: 產出 Sync API Spec Artifact (Contract-First)](https://github.com/AH431/NJ_Stream_ERP/issues/1)  
**Milestone**：W1–W2 Foundation  
**產出檔案**：`docs/api-contract-sync-v1.6.yaml`  
**基準文件**：`docs/NJ_Stream_ERP MVP 同步協定規格 v1.6.md`  
**完成日期**：2026-04-10  
**狀態**：✅ PASS — 可作為前後端開發 Contract-First SSOT

---

## 1. 核心憲法

| 規則 | 規格對應位置 | 狀態 |
|------|------------|------|
| 本地 Drift 為 SSOT | `info.description` 設計哲學 | ✅ |
| operations 依 `created_at` 升序 | `Operation.createdAt` description、`SyncPushRequest.operations` description、400 `REQUEST_ORDER_VIOLATION` | ✅ |
| 單批上限 50 筆 | `SyncPushRequest.operations.maxItems: 50`、400 `BATCH_SIZE_EXCEEDED` | ✅ |
| 非庫存 LWW（以 `updatedAt` 為準） | `OperationType.update` description、`CustomerPayload.updatedAt` description | ✅ |
| 庫存 Delta Update + Fail-to-Pull | `DeltaType` 說明表、`INSUFFICIENT_STOCK` 處理說明 | ✅ |

---

## 2. DELTA_UPDATE 四種 type

| deltaType | `quantity_on_hand` | `quantity_reserved` | 使用情境 | 規格對應 | 狀態 |
|-----------|-------------------|--------------------|---------|---------|----|
| `in`      | + amount           | 不變                | 採購入庫 | `DeltaType` enum description 說明表 | ✅ |
| `reserve` | 不變               | + amount            | 業務確認訂單 | 同上 | ✅ |
| `cancel`  | 不變               | - amount            | 取消已確認訂單 | 同上 | ✅ |
| `out`     | - amount           | - amount            | 實際出貨 | 同上 | ✅ |
| 約束：`quantity_on_hand >= 0` | — | — | `DeltaType.description` 約束條件 | ✅ |
| 約束：`quantity_reserved <= quantity_on_hand` | — | — | 同上 | ✅ |

---

## 3. 錯誤碼處理策略

| 錯誤碼 | HTTP | 前端策略 | `server_state` | 規格對應 | 狀態 |
|--------|------|----------|---------------|---------|------|
| `INSUFFICIENT_STOCK` | 409 | 強制 Pull | `null` | `SyncErrorCode` description、`FailedOperation`、207 example | ✅ |
| `FORBIDDEN_OPERATION` | 403 | Force Overwrite | 必填 | 同上 | ✅ |
| `PERMISSION_DENIED` | 403 | Force Overwrite | 必填 | 同上 | ✅ |
| `VALIDATION_ERROR` | 400 | Force Overwrite | 必填 | 同上 | ✅ |
| `DATA_CONFLICT` | 409 | 人工介入 | 必填 | `SyncErrorCode` description | ✅ |

---

## 4. 特殊業務規則

| 規則 | 規格對應位置 | 狀態 |
|------|------------|------|
| 報價轉訂單不自動觸發 reserve | `SyncPushRequest` description「報價轉訂單特殊規則」、`SalesOrderPayload.status` description | ✅ |
| First-to-Sync wins（轉單併發控制） | `QuotationPayload.status` description、`SalesOrderPayload.quotationId` description | ✅ |
| 軟刪除（禁止 Hard Delete） | `OperationType.delete` description、所有 Payload 的 `deletedAt` description | ✅ |
| 稅額「預估稅額」/「已調整」提示 | `QuotationPayload.taxAmount` description | ✅ |
| MVP 單一倉庫（`warehouseId` 固定 1） | `InventoryItemPayload.warehouseId` description、`InventoryDeltaPayload.warehouseId` | ✅ |
| `processed_operations` 冪等去重 | `Operation.id` description、endpoint 處理流程說明 | ✅ |

---

## 5. Schema 完整性（對應 ERD Schema Final）

| Entity | Payload Schema | 必填欄位 | 軟刪除 `deletedAt` | 狀態 |
|--------|---------------|---------|-------------------|------|
| `customers` | `CustomerPayload` | id, name, createdAt, updatedAt | ✅ | ✅ |
| `products` | `ProductPayload` | id, name, sku, unitPrice, createdAt, updatedAt | ✅ | ✅ |
| `quotations` | `QuotationPayload` | id, customerId, createdBy, items, totalAmount, taxAmount, status, createdAt, updatedAt | ✅ | ✅ |
| `sales_orders` | `SalesOrderPayload` | id, customerId, createdBy, status, createdAt, updatedAt | ✅ | ✅ |
| `inventory_items` | `InventoryItemPayload` | id, productId, warehouseId, quantityOnHand, quantityReserved, createdAt, updatedAt | ✅ | ✅ |
| `inventory_delta` | `InventoryDeltaPayload` | inventoryItemId, productId, warehouseId, amount | N/A | ✅ |

---

## 6. API 設計品質

| 項目 | 說明 | 狀態 |
|------|------|------|
| OpenAPI 版本 | 3.1.0 | ✅ |
| Security Scheme | `BearerAuth` (JWT)，含 role 說明 | ✅ |
| 主端點 | `POST /api/v1/sync/push` | ✅ |
| 部分成功語義 | HTTP 207 Multi-Status（batch 部分失敗） | ✅ |
| 請求層級錯誤 | HTTP 400（格式錯誤、超量、排序違規）獨立於 operation 層級 | ✅ |
| 擴充端點預留 | `GET /api/v1/sync/pull`（W6 實作，含參數設計） | ✅ |
| Decimal 精度 | 金額欄位使用 `string` pattern `^\d+\.\d{2}$`，避免 JS 浮點誤差 | ✅ |
| 冪等性設計 | `operation.id` UUID 去重，重複推送視為成功 | ✅ |
| Examples 涵蓋 | basicPush / deltaUpdateReserve / quotationToOrder / insufficientStock / permissionDenied | ✅ |
| `components/schemas` 拆分 | 所有 entity、error、request/response 均獨立定義，可重用 | ✅ |

---

## 7. 已知限制與後續 TODO

| 項目 | 說明 | 建議處理時機 | 對應 GitHub Issue / Milestone | 優先級 |
|------|------|--------------|-------------------------------|--------|
| `GET /api/v1/sync/pull` 回傳格式 | 目前標注 TBD，需定義 pull 回應結構（包含 entities 陣列與 cursor 分頁機制） | W6 Sprint Planning 前 | W6–W8 SCM | High |
| `FailedOperation.server_state` 的 polymorphic 處理 | 目前使用 oneOf 但缺少 `discriminator`，前端難以依 `entityType` 自動判斷結構 | W3（客戶/產品 CRUD 實作前） | W3–W4 CRUD | High |
| Auth 端點（`/api/v1/auth/login`, `/refresh` 等） | 未在此 sync 規格中定義，建議另立獨立檔案 | W1–W2 Foundation | W1–W2 Foundation | Medium |
| `users` entity 同步規則 | 目前未列入 `entityType`，Admin 使用者管理是否需要離線同步待確認（建議不納入，改用後台管理） | W3 前確認 | W3–W4 CRUD | Medium |

**說明與建議**：
- `server_state` 建議在 `components/schemas` 中使用 `oneOf` + `discriminator` 機制，讓前端能安全地進行 Force Overwrite。
- `users` entity：基於同步協定「本地 Drift 為 SSOT」與角色權限設計，**建議排除**離線同步，避免權限與安全性風險。
- 所有 TODO 項目都會轉為獨立 Issue，並要求在關閉前通過 `sync_logic_check` template。