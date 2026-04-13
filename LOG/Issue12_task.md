# Issue #12 Task List — 確認訂單 → reserve UI 分離

**Milestone**：W6–W8 SCM  
**Agent**：B（前端）  
**前置 Issue**：#11（入庫 UI + Race Condition）已完成 ✅

---

## 範疇說明

| 功能 | Issue #12 |
|------|:---------:|
| `_confirmOrder()` 拆除自動 reserve，加入簡單確認 dialog | ✅ 做 |
| 新增「預留庫存」按鈕（confirmed 訂單）| ✅ 做 |
| `ReserveInventoryDialog`：庫存預覽 + 確認按鈕 | ✅ 做 |
| 取消訂單：cancel delta 邏輯不變（服務端 INSUFFICIENT_STOCK 兜底）| ✅ 不變 |
| 採購訂單 UI | ❌ MVP 不做 |

---

## 設計說明

### 為何要拆分

**現況**：業務點「確認訂單」→ 立即 enqueue reserve，中間無預覽，容易誤觸。  
**Issue #12**：拆成兩個步驟：

```
Step 1：確認訂單（status: pending → confirmed）
  └─ 業務判斷此訂單已核定，標記為已確認
  └─ 不觸發 reserve，庫存不動

Step 2：預留庫存（手動觸發，confirmed 訂單才顯示）
  └─ 顯示 ReserveInventoryDialog：
     - 每行：產品名 + SKU + 預留數量 + 本地庫存快照
     - available < qty → ⚠️ 警示（不阻擋：服務端 INSUFFICIENT_STOCK 最終兜底）
  └─ 業務按「確認預留」→ 才 enqueue inventory_delta:reserve × N
```

### 取消訂單的庫存問題

若訂單是 confirmed 但尚未 reserve，取消時 cancel delta 會送到服務端 →  
服務端 `reserved - amount < 0` → INSUFFICIENT_STOCK → 409 → Force Pull。

**這是可接受的行為**：
- 訂單 status=cancelled 已成功（order:update 是獨立 op）
- cancel delta 失敗 → 標記 failed，庫存數字不變（本就是 0）
- Force Pull 後前端取得最新狀態，業務無感知

→ 取消邏輯**不做修改**，依賴服務端雙重保護。

### 庫存預覽的準確度

ReserveInventoryDialog 顯示的是**本地快照**（最後一次 Pull 的值），非即時。  
若庫存已被其他裝置預留，前端可能顯示「可出貨足夠」但服務端仍回 INSUFFICIENT_STOCK。  
這是離線優先設計的固有特性，用警示文字告知業務需最新數據應先 Pull。

---

## Phase 1：修改 `_confirmOrder()`

**修改**：`lib/features/sales_orders/sales_order_list_screen.dart`

### 1-1. 移除 reserve enqueue

從 `_confirmOrder()` 完整移除以下段落：

```dart
// ❌ 移除
for (final item in items) {
  await sync.enqueueDeltaUpdate('inventory_delta', 'reserve', {
    'productId': item.productId,
    'amount': item.quantity,
  });
}
```

### 1-2. 加入簡單確認 dialog

在讀取 quotation 之前加入 AlertDialog：

```dart
// 確認 dialog（防止誤觸）
final confirmed = await showDialog<bool>(
  context: context,
  builder: (_) => AlertDialog(
    title: const Text('確認訂單'),
    content: const Text(
      '確認後訂單狀態將變更為「已確認」。\n'
      '庫存預留需在確認後另行執行。',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('確認訂單'),
      ),
    ],
  ),
);
if (confirmed != true) return;
```

### 1-3. 更新 SnackBar 文字

```dart
// 舊：'訂單已確認，庫存預留已排入待同步佇列'
// 新：
const SnackBar(content: Text('訂單已確認。請在訂單列表點選「預留庫存」執行庫存預留。'))
```

---

## Phase 2：新增 `ReserveInventoryDialog`

**新增**：`lib/features/sales_orders/reserve_inventory_dialog.dart`

### 2-1. 資料模型（傳入 Dialog）

```dart
class ReserveInventoryDialog extends StatelessWidget {
  final SalesOrder order;
  final List<QuotationItemModel> items;       // 報價明細
  final Map<int, Product> productMap;         // productId → Product
  final Map<int, InventoryItem> inventoryMap; // productId → InventoryItem
}
```

### 2-2. 每行顯示結構

| 欄位 | 說明 |
|------|------|
| 產品名稱 + SKU | 從 productMap 取得 |
| 預留數量 | `item.quantity`（藍色）|
| 可出貨 | `onHand - reserved`（綠色，或「— 無本地記錄」）|
| 警示 | `available < item.quantity` → ⚠️ 橘色 row |

```dart
// 每一行的警示邏輯
final invItem = inventoryMap[item.productId];
final available = invItem != null
    ? invItem.quantityOnHand - invItem.quantityReserved
    : null;
final isWarning = available != null && available < item.quantity;
```

### 2-3. Dialog 結構

```
AlertDialog(
  title: '預留庫存確認',
  content: Column(
    [說明文字：「以下庫存將被預留，確認後不可撤回（需重新取消訂單才能釋放）」]
    [若有任一 ⚠️：'部分商品本地庫存可能不足，建議先同步後再執行']
    [ListView of _buildItemRow()]
  ),
  actions: [取消] [確認預留（FilledButton）]
)
```

### 2-4. 回傳值

- `Navigator.pop(context, true)` → 確認預留
- `Navigator.pop(context, false)` → 取消

---

## Phase 3：新增 `_reserveInventory()` + 按鈕

**修改**：`lib/features/sales_orders/sales_order_list_screen.dart`

### 3-1. 新增 `_reserveInventory()` 方法

```dart
Future<void> _reserveInventory(BuildContext context, SalesOrder order) async {
  final db   = context.read<AppDatabase>();
  final sync = context.read<SyncProvider>();

  // 讀取報價明細
  final quotation = await (db.select(db.quotations)
      ..where((t) => t.id.equals(order.quotationId!))).getSingleOrNull();
  if (quotation == null) { /* SnackBar 提示 */ return; }

  List<QuotationItemModel> items = [];
  try {
    items = (jsonDecode(quotation.items) as List)
        .cast<Map<String, dynamic>>()
        .map(QuotationItemModel.fromJson)
        .toList();
  } catch (_) { /* SnackBar 提示 */ return; }

  if (items.isEmpty) { /* SnackBar 提示 */ return; }

  // 建立 productMap + inventoryMap
  final products   = await db.getActiveProducts();
  final productMap = <int, Product>{for (final p in products) p.id: p};

  final inventoryMap = <int, InventoryItem>{};
  for (final item in items) {
    final inv = await db.getInventoryItemByProductId(item.productId);
    if (inv != null) inventoryMap[item.productId] = inv;
  }

  if (!context.mounted) return;

  // 顯示 ReserveInventoryDialog
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => ReserveInventoryDialog(
      order: order,
      items: items,
      productMap: productMap,
      inventoryMap: inventoryMap,
    ),
  );

  if (confirmed != true) return;

  // enqueue inventory_delta:reserve × N
  for (final item in items) {
    await sync.enqueueDeltaUpdate('inventory_delta', 'reserve', {
      'productId': item.productId,
      'amount': item.quantity,
    });
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('庫存預留已排入待同步佇列')),
    );
  }
}
```

### 3-2. `_buildOrderTile()` 補 canReserve 條件與按鈕

```dart
// 預留庫存：sales/admin、status=confirmed、已同步、有 quotationId
final canReserve = (role == 'sales' || role == 'admin') &&
    order.status == 'confirmed' &&
    !isOffline &&
    order.quotationId != null;
```

```dart
if (canReserve)
  TextButton.icon(
    onPressed: () => _reserveInventory(context, order),
    icon: const Icon(Icons.inventory_outlined, size: 16),
    label: const Text('預留庫存'),
    style: TextButton.styleFrom(foregroundColor: Colors.indigo),
  ),
```

> **按鈕顯示順序**：確認訂單（pending）→ 預留庫存（confirmed）→ 出貨（confirmed, warehouse）→ 取消

### 3-3. import 補充

```dart
import 'package:flutter/material.dart';  // 已有
import '../../database/dao/inventory_items_dao.dart';   // 已有（其他 screen import）
import '../../database/dao/product_dao.dart';           // 已有
import 'reserve_inventory_dialog.dart';                 // 新增
```

---

## Phase 4：驗收

### 4-1. 靜態分析

```
dart analyze lib/features/sales_orders/sales_order_list_screen.dart \
             lib/features/sales_orders/reserve_inventory_dialog.dart
```

預期：0 issues

### 4-2. UI 驗收（行為矩陣）

| 情境 | 操作 | 預期行為 |
|------|------|----------|
| pending 訂單，sales 角色 | 點「確認訂單」| 出現 dialog → 取消 → 無變化 |
| pending 訂單，sales 角色 | 點「確認訂單」→ 確認 | status=confirmed，無 reserve enqueue |
| confirmed 訂單，sales 角色 | 點「預留庫存」| ReserveInventoryDialog 顯示明細 + 庫存快照 |
| 庫存不足（available < qty）| ReserveInventoryDialog | ⚠️ 警示橘色列 + 建議先 Pull 文字 |
| ReserveInventoryDialog 取消 | — | 無 enqueue |
| ReserveInventoryDialog 確認 | — | N 筆 reserve enqueue，SnackBar 提示 |
| confirmed 訂單，warehouse 角色 | 訂單列表 | 只顯示「出貨」按鈕，不顯示「預留庫存」|

### 4-3. curl 驗收

- 確認 `_confirmOrder` 後無 reserve op 在 pendingOperations（DB 查詢）
- 按「預留庫存」→ 確認 → Push → 服務端回 200 succeeded
- GET /pull → quantityReserved 增加

---

## 依賴關係

```
Phase 1（_confirmOrder 移除 reserve + 加 dialog）←── 可先完成
Phase 2（ReserveInventoryDialog 新增）            ←── 可並行
       ↓
Phase 3（_reserveInventory() + canReserve 按鈕）
       ↓
Phase 4（dart analyze + UI 驗收 + curl 驗收）
```

---

## 影響評估

| 現有功能 | 影響 |
|---------|:----:|
| `_cancelOrder`（cancel delta 邏輯）| 不變，服務端 INSUFFICIENT_STOCK 兜底 |
| `_shipOrder`（out delta）| 不變，仍需 confirmed 才能出貨 |
| `InventoryListScreen`（庫存快照）| 不變 |
| `StockInDialog`（入庫）| 不變 |
| Race Condition（409 + Force Pull）| 不變，reserve 仍走相同路徑 |
