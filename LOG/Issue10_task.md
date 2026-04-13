# Issue #10 Task List — 出貨 UI + 庫存列表

**Milestone**：W6–W8 SCM  
**Agent**：B（前端，全部）  
**前置 Issue**：#9（訂單列表 + reserve）已完成 ✅

---

## 範疇說明

| 功能 | Issue #10 |
|------|:---------:|
| SalesOrderListScreen：出貨按鈕（warehouse/admin → type: out）| ✅ |
| InventoryListScreen：庫存快照列表（全角色唯讀）| ✅ |
| HomeScreen 加第五 tab（庫存）| ✅ |
| 入庫 UI（warehouse → type: in）| ❌ 留 Issue #11 |
| 採購訂單 UI | ❌ MVP 不做 |

---

## 前置確認（全部已完成，無須補做）

| 項目 | 來源 |
|------|------|
| 後端 `processInventoryDelta` case `out`（-onHand, -reserved）| Issue #5 ✅ |
| 後端 `processSalesOrder` update status: `shipped` | Issue #5 ✅ |
| 前端 `updateSalesOrderStatus(id, status, {shippedAt})`| Issue #9 ✅ |
| 前端 `enqueueDeltaUpdate('inventory_delta', 'out', payload)` | Issue #9 ✅ |
| 前端 `InventoryItemsDao.watchInventoryItems()` | Issue #9 ✅ |
| 前端 SalesOrderListScreen 基礎架構 | Issue #9 ✅ |

---

## Phase 1：SalesOrderListScreen 補出貨按鈕

**修改**：`lib/features/sales_orders/sales_order_list_screen.dart`

### 1-1. 新增 `_shipOrder()` 方法

**顯示條件**：`role == 'warehouse' || role == 'admin'`  
**且** `order.status == 'confirmed'`  
**且** `order.id > 0`（已同步到後端）  
**且** `order.quotationId != null`（需要 items 計算 out delta）

**執行流程**：

```
AlertDialog 確認（「確認出貨後庫存將立即扣除，是否繼續？」）
  ↓ 確認
1. 查本地 Quotation → 解析 items JSON
2. db.updateSalesOrderStatus(id, 'shipped', shippedAt: now)（樂觀）
3. sync.enqueueUpdate('sales_order', id, {id, status:'shipped', shippedAt, updatedAt})
4. for each item → sync.enqueueDeltaUpdate('inventory_delta', 'out', {productId, amount})
5. Snackbar：「出貨完成，庫存扣除已排入待同步佇列」
```

**邊界情況**：
- Quotation 不在本地 → Snackbar「請先同步再執行出貨」，中止
- items 為空或解析失敗 → Snackbar「無法取得訂單明細，請重新同步」，中止

### 1-2. `_buildOrderTile()` 補 canShip 條件與按鈕

```dart
final canShip = (role == 'warehouse' || role == 'admin') &&
    order.status == 'confirmed' &&
    !isOffline &&
    order.quotationId != null;
```

在操作按鈕列新增：
```dart
if (canShip)
  TextButton.icon(
    onPressed: () => _shipOrder(context, order),
    icon: const Icon(Icons.local_shipping_outlined, size: 16),
    label: const Text('出貨'),
    style: TextButton.styleFrom(foregroundColor: Colors.green),
  ),
```

> **注意**：同一張訂單同時可顯示「取消」（若 confirmed 且 sales/admin）與「出貨」（若 confirmed 且 warehouse/admin）。admin 兩者都有。

---

## Phase 2：InventoryListScreen（新增）

**新增**：`lib/features/inventory/inventory_list_screen.dart`

### 2-1. 功能需求

- 全角色可讀（sales / warehouse / admin 皆顯示此 tab）
- 顯示每個產品的庫存快照
- 需搭配 Product 查詢取得產品名稱 / SKU（與 customerMap 相同模式）

### 2-2. 資料來源

- `db.watchInventoryItems()` → `Stream<List<InventoryItem>>`（productId 升序）
- `db.getActiveProducts()` → 一次性建立 `Map<int, Product>`（productId → Product）

### 2-3. 列表顯示（每列）

| 欄位 | 說明 |
|------|------|
| 產品名稱 + SKU | 從 productMap 取得 |
| 在庫數量 | `quantityOnHand`（藍色數字）|
| 已預留 | `quantityReserved`（橘色數字）|
| 可出貨 | `quantityOnHand - quantityReserved`（綠色數字）|
| 低庫存警示 | `quantityOnHand <= minStockLevel` → 顯示 `⚠️ 低庫存` badge（紅色）|

### 2-4. 狀態處理

- 列表為空 → 顯示「尚無庫存記錄，請先同步」
- Pull-to-refresh → `sync.pullData()`

### 2-5. 只讀限制

- **無 FAB、無刪除、無編輯按鈕**
- 入庫（type: in）按鈕留 Issue #11

---

## Phase 3：HomeScreen 加第五 tab

**修改**：`lib/main.dart`

- [ ] `_titles` 加入 `'庫存查詢'`（index 4）
- [ ] `IndexedStack` 加入 `InventoryListScreen()`
- [ ] `NavigationBar` 加入第五 destination：`Icon(Icons.warehouse_outlined)` / label `'庫存'`
- [ ] `_buildFab`：tab 4 無 FAB（庫存唯讀）
- [ ] import `'features/inventory/inventory_list_screen.dart'`

---

## Phase 4：驗收

### 4-1. 靜態分析

- [ ] `dart analyze lib/main.dart lib/features/sales_orders/sales_order_list_screen.dart lib/features/inventory/inventory_list_screen.dart`：0 issues

### 4-2. curl 驗收（4/4 通過）

**測試環境**：productId=3，起始 onHand=10, reserved=0

| # | 操作 | 預期 | 結果 |
|---|------|------|:----:|
| 1 | `reserve` amount=3 | succeeded，reserved: 0→3 | ✅ |
| 2 | `out` amount=3（正向：reserve 後出貨）| succeeded，onHand: 10→7，reserved: 3→0 | ✅ |
| 3 | `out` amount=8（超限，onHand=7）| INSUFFICIENT_STOCK + server_state | ✅ |
| 4 | `dart analyze` 0 issues | 0 issues | ✅ |

### 4-3. code-verify

- [x] `_shipOrder()` 觸發條件：warehouse/admin + confirmed + id>0 + quotationId!=null
- [x] 出貨後 status chip 顯示綠色「已出貨」（`_buildStatusChip` 已涵蓋 `shipped` case）
- [x] InventoryListScreen 低庫存警示邏輯：`onHand <= minStockLevel`

---

## 設計說明

### out delta 的約束邏輯（後端現有）

```
out：newOnHand = onHand - amount；newReserved = reserved - amount
約束：newOnHand >= 0 && newReserved >= 0 && newReserved <= newOnHand
```

**注意**：out 同時扣 onHand 和 reserved，所以出貨前庫存必須已 reserve（即已確認訂單）。  
若嘗試對未 reserve 的訂單直接出貨（reserved=0 但 amount > 0），`newReserved = 0 - amount < 0` → INSUFFICIENT_STOCK。  
這個約束確保「出貨 = 已確認訂單才能出」的業務語意。

### 可出貨數公式

```
可出貨 = quantityOnHand - quantityReserved
```

InventoryListScreen 顯示此數值，讓倉管直接判斷是否可出貨。

---

## 依賴關係

```
Phase 1（SalesOrderListScreen 出貨）
Phase 2（InventoryListScreen 新增）  ← 兩者可並行
       ↓
Phase 3（HomeScreen 第五 tab）
       ↓
Phase 4（驗收）
```
