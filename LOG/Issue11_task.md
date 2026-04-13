# Issue #11 Task List — 入庫 UI + Race Condition 驗收

**Milestone**：W6–W8 SCM  
**Agent**：B（前端） + curl 驗收  
**前置 Issue**：#10（出貨 UI + 庫存列表）已完成 ✅

---

## 範疇說明

| 功能 | Issue #11 |
|------|:---------:|
| StockInDialog（產品選擇 + 入庫數量）| ✅ |
| InventoryListScreen FAB（warehouse/admin）| ✅ |
| HomeScreen `_buildFab` 補 tab 4 | ✅ |
| Race Condition curl 驗收（兩筆 reserve 競爭同一庫存）| ✅ |
| 採購訂單 UI | ❌ MVP 不做 |

---

## 前置確認（全部已完成）

| 項目 | 來源 |
|------|------|
| 後端 `processInventoryDelta` case `in`（+onHand，不動 reserved）| Issue #5 ✅ |
| 前端 `enqueueDeltaUpdate('inventory_delta', 'in', payload)` | Issue #9 ✅ |
| 前端 `InventoryItemsDao.watchInventoryItems()` | Issue #9 ✅ |
| 前端 `ProductDao.getActiveProducts()` | Issue #5 ✅ |
| 前端 `InventoryListScreen` 基礎架構 | Issue #10 ✅ |

---

## 設計決策

### 為何不做本地樂觀更新

`in` 操作更新的是 `inventory_items.quantity_on_hand`，此欄位只能由後端透過 DELTA_UPDATE 修改，前端沒有直接寫入的合法路徑（也沒有 `updateInventoryItem` DAO 方法）。

→ 只 enqueue，同步後 Pull 才更新畫面。InventoryListScreen 顯示「同步中」的舊值是預期行為，和「出貨」的樂觀設計刻意相反：庫存數字需伺服器確認後才更新，避免顯示錯誤庫存造成誤判。

### 產品選單範圍

只顯示**本地 Drift 有對應 `inventory_items` 記錄**的產品（透過 `inventoryItems` 表的 `productId` 做 filter），避免選到沒有庫存記錄的產品導致 `DATA_CONFLICT`。

實作方式：
```dart
// 取得有庫存記錄的 productId set
final invItems = await db.watchInventoryItems().first;
final validProductIds = invItems.map((i) => i.productId).toSet();
// 從 productMap 只保留 validProductIds 的產品
final eligibleProducts = productMap.values.where((p) => validProductIds.contains(p.id)).toList();
```

---

## Phase 1：StockInDialog

**新增**：`lib/features/inventory/stock_in_dialog.dart`

### 1-1. 對話框結構（AlertDialog + StatefulWidget）

```dart
class StockInDialog extends StatefulWidget {
  const StockInDialog({super.key});
}
```

### 1-2. 狀態

```dart
int? _selectedProductId;
final _amountController = TextEditingController();
final _formKey = GlobalKey<FormState>();
List<Product> _eligibleProducts = [];   // 有庫存記錄的產品
bool _loading = true;
```

### 1-3. initState：載入有庫存記錄的產品

- [ ] `db.watchInventoryItems().first` → 取得 productId set
- [ ] `db.getActiveProducts()` → filter 出 validProductIds 的產品
- [ ] 結果存入 `_eligibleProducts`，`_loading = false`

### 1-4. UI

- [ ] `DropdownButtonFormField<int>`：選項 = `_eligibleProducts`（顯示 `name（SKU）`）
  - validator：必選
- [ ] `TextFormField`：輸入入庫數量
  - keyboardType: `TextInputType.number`
  - validator：必填、必須為正整數（`int.tryParse(v) != null && int.parse(v) > 0`）
- [ ] AlertDialog actions：「取消」/ 「確認入庫」

### 1-5. 提交流程

```
_formKey.validate() 通過後：
1. sync.enqueueDeltaUpdate('inventory_delta', 'in', {
     'productId': _selectedProductId,
     'amount': int.parse(_amountController.text),
   })
2. Navigator.pop(context)
3. Snackbar（由呼叫端顯示）：「入庫已排入待同步佇列，同步後庫存將更新」
```

---

## Phase 2：InventoryListScreen FAB 整合

**修改**：`lib/main.dart` — `_buildFab()` 方法

在最後 `return null` 之前新增：

```dart
if (_selectedIndex == 4 && (role == 'warehouse' || role == 'admin')) {
  return FloatingActionButton(
    heroTag: 'fab_stock_in',
    onPressed: () async {
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => const StockInDialog(),
      );
      if (result == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('入庫已排入待同步佇列，同步後庫存將更新')),
        );
      }
    },
    tooltip: '入庫',
    child: const Icon(Icons.add_box_outlined),
  );
}
```

- [ ] import `'features/inventory/stock_in_dialog.dart'`

> **注意**：`StockInDialog` 在 pop 時回傳 `Navigator.pop(context, true)`，由 `_buildFab` 的 `result == true` 判斷是否顯示 Snackbar。

---

## Phase 3：驗收

### 3-1. 靜態分析

- [ ] `dart analyze lib/main.dart lib/features/inventory/stock_in_dialog.dart lib/features/inventory/inventory_list_screen.dart`：0 issues

### 3-2. curl 驗收 — in（入庫正向）

**前置**：productId=3，DB 現況 onHand=7（Issue #10 驗收後）

- [ ] `POST /push` `inventory_delta:delta_update` type:`in` amount=5
  - 預期：`succeeded`，onHand: 7→12，reserved 不變
  - 確認 DB：`SELECT quantity_on_hand, quantity_reserved FROM inventory_items WHERE product_id=3`

### 3-3. curl 驗收 — Race Condition（#12 收尾）

模擬兩台裝置同時 reserve，只有一台能成功（INSUFFICIENT_STOCK）。

**前置**：確認 onHand=12, reserved=0（3-2 完成後）

**情境**：裝置 A reserve 10（合法），裝置 B 同時 reserve 5（10+5=15 > 12 → 超限）

- [ ] **操作 1（合批送出，升序排列）**：同一 push 內送兩筆 reserve
  ```json
  operations: [
    { deltaType:"reserve", amount: 10, createdAt: "T+0" },
    { deltaType:"reserve", amount:  5, createdAt: "T+1" }
  ]
  ```
  - 預期：第一筆 succeeded（reserved: 0→10），第二筆 INSUFFICIENT_STOCK（10+5=15 > 12）
  - 回傳：`{ succeeded: ["op1"], failed: [{ code:"INSUFFICIENT_STOCK", server_state: {onHand:12, reserved:10} }] }`

- [ ] **GET /pull 確認**：`inventoryItems[0].quantityReserved == 10`

> **Race Condition 結論**：同一批次內，Drizzle transaction 每筆獨立，順序執行（非並發），第一筆先改 DB，第二筆讀到已更新的 reserved=10，應用層攔截 INSUFFICIENT_STOCK。這是「批內序列化」而非真正並發競爭，真實的跨裝置競爭需依賴 DB transaction isolation（PostgreSQL 預設 READ COMMITTED）。

---

## 依賴關係

```
Phase 1（StockInDialog）←─── 可先完成
Phase 2（_buildFab 補 tab 4）←─ 依賴 Phase 1
       ↓
Phase 3（驗收：dart analyze + curl in + Race Condition）
```
