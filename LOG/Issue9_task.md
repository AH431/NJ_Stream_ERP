# Issue #9 Task List — SCM 基礎建設：訂單列表 + 確認訂單 → reserve

**Milestone**：W6–W8 SCM  
**Agents**：A（後端前置） + B（前端主體）  
**前置 Issue**：#8（報價單 UI）已完成 ✅

---

## 範疇說明

| 功能 | Issue #9 |
|------|:--------:|
| 後端 GET /pull 補 inventoryItems 增量查詢 | ✅ |
| 前端 schema 補齊 InventoryItems.minStockLevel（migration） | ✅ |
| InventoryItemsDao（watch / get / upsert） | ✅ |
| SalesOrderDao 擴充（watchActiveSalesOrders / updateSalesOrderStatus） | ✅ |
| SyncProvider：enqueueDeltaUpdate | ✅ |
| SyncProvider：INSUFFICIENT_STOCK → 自動 pullData()（Fail-to-Pull） | ✅ |
| SyncProvider：pullData() 補 inventoryItems | ✅ |
| SalesOrderListScreen（列表 + 確認訂單 + 取消訂單） | ✅ |
| HomeScreen 加第四 tab（訂單管理） | ✅ |
| 庫存列表 UI（InventoryListScreen） | ❌ 留 Issue #11 |
| 出貨 UI（type: out） | ❌ 留 Issue #10 |
| 採購入庫 UI（type: in） | ❌ 留 Issue #11 |

---

## 前置確認

### 已完成（不須重做）

| 項目 | 來源 |
|------|------|
| 後端 `processInventoryDelta`（reserve / cancel / out / in）4 種 type | Issue #5 ✅ |
| 後端 `processSalesOrder` update（status: confirmed / shipped / cancelled）| Issue #5 ✅ |
| 前端 `InventoryItems` Drift table | Issue #3 ✅ |
| 前端 `InventoryDeltas` Drift table | Issue #3 ✅ |
| 前端 `PendingOperations.deltaType` 欄位 | Issue #3 ✅ |
| 前端 `SyncProvider.enqueueUpdate()` | Issue #5 ✅ |

### 已識別缺口（Issue #9 需補）

| 缺口 | 詳細說明 |
|------|---------|
| **Schema 不符**：前端 `InventoryItems` 缺 `minStockLevel` 欄位 | 後端 `inventory_items` 有此欄，前端需補欄 + migration |
| **後端 GET /pull 未回傳 inventoryItems** | `result.inventoryDeltas` 永遠空陣列，需補增量查詢 + key 改為 `inventoryItems` |
| **前端缺 InventoryItemsDao** | 無法 watch / upsert 庫存快照 |
| **前端 SalesOrderDao 僅最小範疇** | 缺 `watchActiveSalesOrders()` / `updateSalesOrderStatus()` |
| **前端 SyncProvider 缺 `enqueueDeltaUpdate`** | 無法排入 inventory_delta 操作 |
| **前端 INSUFFICIENT_STOCK 未觸發 Fail-to-Pull** | `_handleError` 只標記 failed，缺自動 pullData() |

---

## 前置工作 — Agent A（後端）

**檔案**：`packages/backend/src/routes/sync.route.ts`

### A-1. Import inventoryItems schema

- [ ] `import { inventoryItems } from '@/schemas/inventory_items.schema.js';`（加入現有 import 群組）

### A-2. 補充 GET /pull inventoryItems 增量查詢

**位置**：`GET /pull` handler，`result` 初始化後

- [ ] 將 `result.inventoryDeltas: []` 改為 `result.inventoryItems: []`（key 名對齊）
- [ ] 新增查詢區塊：

```ts
if (types.includes('inventory_delta')) {
  const rows = await db.select().from(inventoryItems)
    .where(gt(inventoryItems.updatedAt, sinceDate));
  result.inventoryItems = rows.map(r => ({
    entityType: 'inventory_item',
    id: r.id,
    productId: r.productId,
    warehouseId: r.warehouseId,
    quantityOnHand: r.quantityOnHand,
    quantityReserved: r.quantityReserved,
    minStockLevel: r.minStockLevel,
    createdAt: r.createdAt.toISOString(),
    updatedAt: r.updatedAt.toISOString(),
  }));
}
```

### A-3. 驗收

- [ ] `npm run build` TypeScript 無型別錯誤
- [ ] curl `GET /api/v1/sync/pull?entityTypes=inventory_delta` → `inventoryItems` 有資料（需先確認 DB 中有 inventory_items 記錄）

---

## Phase 0：前端 Schema Migration — 補 minStockLevel

**修改**：`packages/frontend/lib/database/schema.dart`  
**修改**：`packages/frontend/lib/database/database.dart`

> **背景**：後端 `inventory_items` 表有 `minStockLevel` 欄位，前端 Drift `InventoryItems` 缺此欄，
> Pull 時無法儲存低庫存警示閾值，且 upsert 資料會不完整。

### 0-1. schema.dart：補 minStockLevel 欄位

**位置**：`InventoryItems` class

- [ ] 新增欄位（緊接在 `quantityReserved` 之後）：
  ```dart
  IntColumn get minStockLevel => integer().withDefault(const Constant(0))();
  ```

### 0-2. database.dart：版本升至 3，補 migration

**位置**：`AppDatabase`

- [ ] `schemaVersion: 3`
- [ ] 在 `MigrationStrategy` 中新增 `from < 3` migration：
  ```dart
  if (from < 3) {
    await m.addColumn(inventoryItems, inventoryItems.minStockLevel);
  }
  ```

### 0-3. 重跑 build_runner

- [ ] `flutter pub run build_runner build --delete-conflicting-outputs`
- [ ] 確認 `database.g.dart` 重新生成（`InsertInventoryItem` / `InventoryItemsCompanion` 含 minStockLevel）

---

## Phase 1：InventoryItemsDao（新增）

**新增檔案**：`lib/database/dao/inventory_items_dao.dart`

```dart
extension InventoryItemsDao on AppDatabase {
  // Read
  Stream<List<InventoryItem>> watchInventoryItems();
  Future<InventoryItem?> getInventoryItemByProductId(int productId);

  // Write
  Future<void> upsertInventoryItemFromServer(InventoryItemsCompanion companion);
}
```

- [ ] `watchInventoryItems()`：`SELECT * FROM inventory_items`，依 `productId` 升序，回傳 Stream
- [ ] `getInventoryItemByProductId(int productId)`：`WHERE productId = ?`，getSingleOrNull()
- [ ] `upsertInventoryItemFromServer(InventoryItemsCompanion companion)`：LWW upsert（同 CustomerDao 模式，依 updatedAt 判斷）

---

## Phase 2：SalesOrderDao 擴充

**修改**：`lib/database/dao/sales_order_dao.dart`

新增兩個方法（保留既有 `insertSalesOrder` / `upsertSalesOrderFromServer`）：

- [ ] `watchActiveSalesOrders()`：
  - `WHERE deleted_at IS NULL`
  - `ORDER BY updatedAt DESC`
  - 回傳 `Stream<List<SalesOrder>>`

- [ ] `updateSalesOrderStatus(int id, String status, {DateTime? confirmedAt, DateTime? shippedAt})`：
  - 樂觀更新：寫入 status + updatedAt（+ confirmedAt / shippedAt 若非 null）
  - 回傳 `Future<void>`

---

## Phase 3：SyncProvider 擴充

**修改**：`lib/providers/sync_provider.dart`

### 3-1. 新增 enqueueDeltaUpdate

```dart
Future<void> enqueueDeltaUpdate(
  String entityType,         // 'inventory_delta'
  String deltaType,          // 'reserve' | 'cancel' | 'out' | 'in'
  Map<String, dynamic> payload,
) async {
  final opId = _uuid.v4();
  final now = DateTime.now().toUtc();
  await _db.into(_db.pendingOperations).insert(
    PendingOperationsCompanion(
      operationId: Value(opId),
      entityType: Value(entityType),
      operationType: Value('delta_update'),
      deltaType: Value(deltaType),
      payload: Value(jsonEncode(payload)),
      createdAt: Value(now),
      relatedEntityId: Value('$entityType:${payload["productId"]}'),
    ),
  );
  final count = await _countPending();
  _emit(_state.copyWith(pendingCount: count));
}
```

- [ ] 實作上述方法

### 3-2. pullData() 補 inventory_item

- [ ] `entityTypes` 改為 `'customer,product,quotation,sales_order,inventory_delta'`
- [ ] 解析 `data['inventoryItems']`：
  ```dart
  final rawInventoryItems = (data['inventoryItems'] as List?)
      ?.cast<Map<String, dynamic>>() ?? [];
  ```
- [ ] 在 for 迴圈後加：
  ```dart
  for (var inv in rawInventoryItems) {
    await _applyForceOverwrite('inventory_item', inv);
  }
  ```

### 3-3. _applyForceOverwrite 補 inventory_item case

- [ ] 新增 `else if (entityType == 'inventory_item')` 區塊：
  ```dart
  } else if (entityType == 'inventory_item') {
    await _db.upsertInventoryItemFromServer(InventoryItemsCompanion(
      id: Value(data['id'] as int),
      productId: Value(data['productId'] as int),
      warehouseId: Value(data['warehouseId'] as int),
      quantityOnHand: Value(data['quantityOnHand'] as int),
      quantityReserved: Value(data['quantityReserved'] as int),
      minStockLevel: Value(data['minStockLevel'] as int),
      createdAt: Value(DateTime.parse(data['createdAt'] as String)),
      updatedAt: Value(DateTime.parse(data['updatedAt'] as String)),
    ));
  }
  ```

### 3-4. _handleError：INSUFFICIENT_STOCK → Fail-to-Pull

**位置**：`_handleError` switch 的 `INSUFFICIENT_STOCK` case

- [ ] 修改為：
  ```dart
  case 'INSUFFICIENT_STOCK':
    await _updateOpStatus(op, 'failed', error: errorCode);
    // 同步協定 v1.6 §6：INSUFFICIENT_STOCK → 強制 Pull 最新庫存狀態
    await pullData();
  ```

---

## Phase 4：SalesOrderListScreen（新增）

**新增檔案**：`lib/features/sales_orders/sales_order_list_screen.dart`

### 4-1. 狀態管理

```dart
Map<int, String> _customerMap = {};   // id → name，一次載入避免 N+1
```

- `initState`：呼叫 `db.getActiveCustomers()` 建立 `_customerMap`

### 4-2. StreamBuilder 列表

- [ ] `StreamBuilder<List<SalesOrder>>` 監聽 `db.watchActiveSalesOrders()`
- [ ] 每列顯示：
  - 客戶名（從 `_customerMap[order.customerId]`）
  - 狀態 Chip（顏色見下表）
  - 訂單建立日期
  - 來源標記：`order.quotationId != null` → "報價轉入" badge
  - 離線 icon：`order.id < 0` → `cloud_upload_outlined`（橘色）

| 狀態 | Chip 顏色 |
|------|-----------|
| pending | 灰（`Colors.grey`）|
| confirmed | 藍（`Colors.blue`）|
| shipped | 綠（`Colors.green`）|
| cancelled | 紅（`Colors.red`）|

### 4-3. 確認訂單（Confirm）

**顯示條件**：`role == 'sales' || role == 'admin'` **且** `order.status == 'pending'` **且** `order.id > 0`（已同步）**且** `order.quotationId != null`

**執行流程**：

- [ ] 從本地 Drift DB 查詢對應 `Quotation`（`db.select().from(quotations).where(id == order.quotationId)`）
- [ ] 解析 `quotation.items`（JSON String → `List<QuotationItemModel>`）
- [ ] 本地樂觀更新：`db.updateSalesOrderStatus(order.id, 'confirmed', confirmedAt: now)`
- [ ] Enqueue `sales_order:update`：
  ```dart
  sync.enqueueUpdate('sales_order', order.id, {
    'id': order.id,
    'status': 'confirmed',
    'confirmedAt': now.toIso8601String(),
    'updatedAt': now.toIso8601String(),
  });
  ```
- [ ] 對每個 QuotationItemModel enqueue `inventory_delta:delta_update`：
  ```dart
  sync.enqueueDeltaUpdate('inventory_delta', 'reserve', {
    'productId': item.productId,
    'amount': item.quantity,
  });
  ```
- [ ] Snackbar：「訂單已確認，庫存預留已排入待同步佇列」

> **注意**：若 `order.quotationId == null`（直接建單），「確認訂單」按鈕不顯示（無法取得 items 計算 reserve）。

### 4-4. 取消訂單（Cancel）

**顯示條件**：`role == 'sales' || role == 'admin'` **且** `order.status == 'pending' || order.status == 'confirmed'` **且** `order.id > 0`

**執行流程**：

- [ ] AlertDialog 確認（避免誤觸）
- [ ] 本地樂觀更新：`db.updateSalesOrderStatus(order.id, 'cancelled')`
- [ ] Enqueue `sales_order:update`：status: 'cancelled'
- [ ] 若原 status 為 `'confirmed'`（已有 reserve）：
  - 從本地 Quotation 解析 items → 對每個 item enqueue `inventory_delta:delta_update` type:`cancel`
  - Snackbar：「訂單已取消，庫存預留釋放已排入待同步佇列」
- [ ] 若原 status 為 `'pending'`（尚未 reserve）：
  - 只 enqueue 訂單 update，不需 cancel delta
  - Snackbar：「訂單已取消」

---

## Phase 5：HomeScreen 更新

**修改**：`lib/main.dart`

- [ ] `_titles` 加入 `'訂單管理'`（index 3）
- [ ] `IndexedStack` 加入 `SalesOrderListScreen()`
- [ ] `NavigationBar` 加入第四 destination：`Icon(Icons.shopping_bag_outlined)` / label `'訂單'`
- [ ] `_buildFab`：tab 3 無 FAB（訂單只能從報價轉入，無直接新增入口）
- [ ] import `'features/sales_orders/sales_order_list_screen.dart'`

---

## Phase 6：驗收

### 6-1. 靜態分析

- [ ] `dart analyze`（via `database.dart` entry point）：0 errors
- [ ] `npm run build`（後端）：TypeScript 無型別錯誤

### 6-2. Schema migration 驗收

- [ ] `flutter pub run build_runner build` 無錯誤
- [ ] `InventoryItemsCompanion` 含 `minStockLevel` 欄位（inspect `database.g.dart`）
- [ ] 確認 `schemaVersion: 3`，migration from < 3 存在

### 6-3. Unit Test — reserve 計算

**新增**：`test/reserve_enqueue_test.dart`

測試目標：確認 `enqueueDeltaUpdate` payload 正確組裝

```
Quotation items：[{productId: 1, quantity: 3, unitPrice: "100.00", subtotal: "300.00"}]
確認訂單後 → enqueue reserve payload = {productId: 1, amount: 3}
```

- [ ] 至少 1 個測試案例（正向：有 quotationId）
- [ ] 1 個負向案例：quotationId == null → 確認訂單按鈕不存在（widget test 可選）

### 6-4. curl 驗收

- [ ] `GET /api/v1/sync/pull?entityTypes=inventory_delta` → `inventoryItems` 非空（需 DB 有資料）
- [ ] `POST /push` reserve → 後端 `quantityReserved` 增加
- [ ] `POST /push` reserve（庫存不足）→ 後端回 INSUFFICIENT_STOCK → 前端自動觸發 pullData()（log 確認）
- [ ] `POST /push` cancel → `quantityReserved` 減少

---

## 範疇邊界（Issue #9 明確不做）

| 不做項目 | 原因 / 留置 Issue |
|---------|-----------------|
| 庫存列表 UI（InventoryListScreen） | Issue #11 |
| 出貨 UI（type: out）| Issue #10 |
| 採購入庫 UI（type: in）| Issue #11 |
| `quotationId == null` 訂單的確認流程 | 無 items 來源，MVP 不支援 |
| Quotation items 完整 Pull（order_items join）| Issue #10（原規劃 W5 Issue #10）|

---

## 技術注意事項

### Inventory Reserve payload 格式

後端 `InventoryDeltaSchema` 只需 `productId` + `amount`：
```ts
const InventoryDeltaSchema = z.object({
  productId: z.number().int().positive(),
  inventoryItemId: z.number().int().positive().optional(), // 選填
  amount: z.number().int().positive(),
});
```
前端 enqueue 時無需查詢 `inventoryItemId`，直接傳 `{productId, amount}`。

### Fail-to-Pull 觸發點

`_handleError` 中的 `INSUFFICIENT_STOCK` 觸發 `pullData()`，但 `pullData()` 本身也有 `_state.status == SyncStatus.syncing` 保護（push 正在進行中時會跳過）。
需確保 `pullData()` 在 `pushPendingOperations()` 完成後才被觸發，或接受「syncing 中跳過 pull」的行為（下次手動 pull 補齊）。

**建議**：Phase 3-4 的 `pullData()` 直接呼叫，不加 await 等待（非阻塞），INSUFFICIENT_STOCK 後 UI 顯示提示即可，pull 結果異步更新。
改為：
```dart
case 'INSUFFICIENT_STOCK':
  await _updateOpStatus(op, 'failed', error: errorCode);
  unawaited(pullData()); // 非阻塞，允許 syncing 時跳過
```

### 確認訂單的 Quotation 查詢

`SalesOrderListScreen` 需要查詢 `Quotation` 來取得 items：
- 使用 `(db.select(db.quotations)..where((t) => t.id.equals(order.quotationId!))).getSingleOrNull()`
- 若 Quotation 不在本地（未 pull）→ 提示「請先同步後再確認」，按鈕呈 disabled

---

## 依賴關係圖

```
前置 Agent A → 後端 GET /pull 補 inventoryItems
       ↓（可並行）
Phase 0 → schema migration（schemaVersion 3）
       ↓
Phase 1 → InventoryItemsDao
Phase 2 → SalesOrderDao 擴充
Phase 3 → SyncProvider 擴充（依賴 Phase 0 + Phase 1 的 upsertInventoryItemFromServer）
       ↓
Phase 4 → SalesOrderListScreen（依賴 Phase 2 + Phase 3）
Phase 5 → HomeScreen 更新（依賴 Phase 4）
       ↓
Phase 6 → 驗收
```
