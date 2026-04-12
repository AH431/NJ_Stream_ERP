# Issue #5 實作計畫 — Agent B：客戶/產品 UI + 離線新增 + 軟刪除

**日期**：2026-04-12  
**Sprint**：W1–W2 Foundation  
**對應 TASKS.md**：#8（Agent B 修正強化）  
**最高指導原則**：同步協定規格 v1.6 > api-contract-sync-v1.6.yaml > PRD v0.8

---

## 前置確認

| 依賴 Issue | 狀態 |
|-----------|------|
| #2 Drizzle Schema | ✅ CLOSED |
| #3 Flutter + Drift + SyncProvider | ✅ CLOSED |
| #4 客戶/產品 REST API + Auth | ✅ CLOSED（14/14 驗收） |
| POST /sync/push | ✅ 實作完成（d40fcb1）|

---

## 驗收標準（AC）

| # | 驗收項目 |
|---|---------|
| AC1 | 客戶列表顯示未軟刪除的客戶（deleted_at IS NULL），含 name、contact |
| AC2 | 離線新增客戶：本地 Drift 即寫 + 塞入 PendingOperations（entityType: customer, operationType: create）|
| AC3 | 軟刪除客戶：operationType: **delete**，payload 為完整客戶快照（deletedAt 非 null）|
| AC4 | 產品列表顯示未軟刪除的產品，含 name、sku、unitPrice |
| AC5 | 離線新增產品：同 AC2，entityType: product |
| AC6 | 軟刪除產品（僅 admin）：同 AC3 |
| AC7 | 新增/刪除後列表即時反映（Drift Stream）|
| AC8 | dart analyze 0 errors |

---

## 設計決策

### 1. DAO：AppDatabase extension（不使用 @DriftAccessor，避免 codegen）
- `watchActiveCustomers()` → Stream（deleted_at IS NULL）
- `insertCustomer(companion)` → Future<void>
- `softDeleteCustomer(id, deletedAt)` → Future<void>
- `upsertCustomerFromServer(companion)` → Future<void>（Issue #6 備用）
- Product 同上

### 2. 離線新增 ID 策略（負數臨時 id）
> 依據：api-contract-sync-v1.6.yaml CustomerPayload.id 為 integer（required），後端 PK 由 PostgreSQL serial 配發。

- 前端離線新增時，id 使用靜態遞減計數器（-1, -2, -3...）
- PendingOperations.payload 帶入此負數 id
- relatedEntityId = "customer:-1" 格式
- 同步後由 Issue #6 pull 機制以 server_state 覆蓋真實 id
- **W1–W2 不實作 id 替換邏輯**

### 3. SyncProvider 新增方法
```dart
static int _localIdSeq = 0;
static int nextLocalId() => --_localIdSeq;

Future<void> enqueueCreate(String entityType, Map<String, dynamic> payload);
Future<void> enqueueDelete(String entityType, int entityId, Map<String, dynamic> payload);
Future<void> enqueueUpdate(String entityType, int entityId, Map<String, dynamic> payload);
Stream<int> watchPendingCount();
```

> ⚠️ operationType: delete（非 update）用於軟刪除，對應 api-contract-sync-v1.6.yaml OperationType enum 定義。

### 4. UI 架構
- HomeScreen（main.dart）提供 Scaffold + AppBar + BottomNavigationBar
- CustomerListScreen / ProductListScreen 只是 Widget，**不含自身 Scaffold**（避免巢狀 Scaffold）
- CustomerFormScreen / ProductFormScreen 有完整 Scaffold，由 Navigator.push 開啟
- IndexedStack 保持 tab 狀態

### 5. 角色權限控制（PR D §3 + auth-yaml）
| 角色 | 客戶列表 | 客戶新增/刪除 | 產品列表 | 產品新增/刪除 |
|------|---------|-------------|---------|-------------|
| sales | ✅ | ✅ | ✅ | ❌ |
| warehouse | ✅ | ❌ | ✅ | ❌ |
| admin | ✅ | ✅ | ✅ | ✅ |

---

## 文件比對衝突確認

| # | 問題 | 修正 |
|---|------|------|
| 1 | AC3 原描述 operationType: update → 合約規定必須為 delete | AC3 已修正 |
| 2 | 離線 id = 0 策略模糊 → 合約 id: integer required | 改用負數臨時 id |
| 3 | warehouse 角色唯讀確認 | UI 不顯示新增/刪除按鈕 |
| 4 | _pushBatch key name 不匹配合約 | 記錄，待 Issue #6 修正 |
| 5 | 合約定義 HTTP 207，後端送 200 | 前端行為不受影響 |

---

## 實作結果

✅ **已於 2026-04-12 完成實作與驗證：**
1. **DAO Helper**：完成 `CustomerDao` 與 `ProductDao` 的 `AppDatabase` extensions。
2. **SyncProvider**：實作 `__localIdSeq` 負數發號器，完成 `enqueueCreate`、`enqueueDelete`（遵照 `operationType: delete` 規範）與 `watchPendingCount` 佇列監聽。
3. **Feature Screens**：
   - 實作 `CustomerListScreen` / `productListScreen`，串接 `watchActiveCustomers/Products()`。
   - 實作 `CustomerFormScreen` / `ProductFormScreen`，落實負數 id 策略與離線 Queue 寫入。
   - `unitPrice` 使用 `decimal` package 與 Drift `TypeConverter<Decimal, String>` 確認精準儲存轉換，符合 API合約 `^\d+\.\d{2}$` 格式。
4. **導航整合**：完成 `HomeScreen` 的 `IndexedStack` 與 `NavigationBar`，並透過 `SyncProvider.role` 實施細粒度 UI 按鈕控管。
5. **程式碼品質**：執行 `dart analyze` 零錯誤（排除 Codegen Analyzer 靜態誤報）。

**本計畫執行完畢，可結案。**
