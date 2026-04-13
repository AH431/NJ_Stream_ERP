# Issue #13 Task List — 出貨 UI（type: out）ShipOrderDialog

**Milestone**：W6–W8 SCM  
**Agent**：B（前端）  
**前置 Issue**：#12（確認訂單 → reserve UI 分離）已完成 ✅

---

## 範疇說明

| 功能 | 說明 |
|------|------|
| `_shipOrder()` 升級：以 ShipOrderDialog 取代簡易 AlertDialog | ✅ 做 |
| `ShipOrderDialog`：雙欄扣減預覽（onHand / reserved 同步顯示）| ✅ 做 |
| 警示 1：`reservedQty < shippingQty` → 未執行 reserve，服務端將拒絕 | ✅ 做 |
| 警示 2：`onHandQty < shippingQty` → 在庫不足（服務端 INSUFFICIENT_STOCK）| ✅ 做 |
| 後端 `out` 邏輯 | ❌ 不改（已正確：`onHand -= amount; reserved -= amount`）|

---

## 設計說明

### 後端 out delta 行為（已驗收，不變）

```
OUT delta：
  newOnHand  = onHand  - amount
  newReserved = reserved - amount

約束（違反 → INSUFFICIENT_STOCK → 409 → Force Pull）：
  newOnHand  >= 0
  newReserved >= 0
  newReserved <= newOnHand
```

關鍵：`reserved -= amount` 表示出貨**同時釋放預留**。  
若業務跳過 reserve 直接出貨 → `reserved - amount < 0` → 服務端 INSUFFICIENT_STOCK。  
Dialog 應提前警示此情況，讓倉管知道風險。

### 為何需要 ShipOrderDialog

現況 `_shipOrder()` 只顯示「庫存將立即扣除，不可逆」文字，倉管無法確認：
- 每件商品實際出貨數量
- 出貨後 onHand / reserved 剩多少
- 是否已完成 reserve（未 reserve 直接出貨會被服務端拒絕）

比對 Issue #12 的 ReserveInventoryDialog，出貨前也應有對等的預覽確認。

### 庫存快照的準確度

ShipOrderDialog 顯示的是**本地快照**（最後一次 Pull 的值）。  
若其他裝置已異動庫存，前端可能顯示「可出貨」但服務端仍回 INSUFFICIENT_STOCK。  
同 #12 設計：警示文字告知建議先 Pull。

---

## Phase 1：新增 `ShipOrderDialog`

**新增**：`lib/features/sales_orders/ship_order_dialog.dart`

### 1-1. 資料模型（傳入 Dialog）

```dart
class ShipOrderDialog extends StatelessWidget {
  final SalesOrder order;
  final List<QuotationItemModel> items;       // 出貨明細
  final Map<int, Product> productMap;         // productId → Product
  final Map<int, InventoryItem> inventoryMap; // productId → InventoryItem
}
```

### 1-2. 每行顯示結構

| 欄位 | 說明 |
|------|------|
| 產品名稱 + SKU | 從 productMap 取得 |
| 出貨數量 | `item.quantity`（藍色）|
| 出貨後在庫 | `onHand - quantity`（綠色，或「— 無本地記錄」）|
| 出貨後預留 | `reserved - quantity`（灰色）|
| 警示 A | `reserved < quantity` → ⚠️ 橘色「尚未預留，服務端將拒絕出貨」|
| 警示 B | `onHand < quantity` → 🔴 紅色「在庫不足」|

```dart
// 每行警示邏輯
final inv = inventoryMap[item.productId];
final postOnHand   = inv != null ? inv.quantityOnHand   - item.quantity : null;
final postReserved = inv != null ? inv.quantityReserved - item.quantity : null;

final isNotReserved = inv != null && inv.quantityReserved < item.quantity;
final isInsufficient = inv != null && inv.quantityOnHand  < item.quantity;
```

### 1-3. Dialog 結構

```
AlertDialog(
  title: '出貨確認',
  content: Column(
    [說明文字：「確認後庫存在庫數量與預留數量將同步扣除，此操作不可逆。」]
    [若有 isNotReserved：⚠️「部分商品尚未執行庫存預留，出貨後服務端將拒絕並觸發強制同步。」]
    [若有 isInsufficient：🔴「部分商品在庫數量不足，建議先確認庫存後再執行出貨。」]
    [ListView of _buildItemRow()]
  ),
  actions: [取消] [確認出貨（FilledButton，色：green）]
)
```

### 1-4. 回傳值

- `Navigator.pop(context, true)` → 確認出貨
- `Navigator.pop(context, false)` → 取消

---

## Phase 2：更新 `_shipOrder()`

**修改**：`lib/features/sales_orders/sales_order_list_screen.dart`

### 2-1. 原始 AlertDialog → 改為載入資料後顯示 ShipOrderDialog

```dart
Future<void> _shipOrder(BuildContext context, SalesOrder order) async {
  final db   = context.read<AppDatabase>();
  final sync = context.read<SyncProvider>();

  // 讀取報價明細
  final quotation = await (db.select(db.quotations)
      ..where((t) => t.id.equals(order.quotationId!))).getSingleOrNull();
  if (quotation == null) { /* SnackBar */ return; }

  List<QuotationItemModel> items = [];
  try {
    items = (jsonDecode(quotation.items) as List)
        .cast<Map<String, dynamic>>()
        .map(QuotationItemModel.fromJson)
        .toList();
  } catch (_) { /* SnackBar */ return; }

  if (items.isEmpty) { /* SnackBar */ return; }

  // 建立 productMap + inventoryMap
  final products   = await db.getActiveProducts();
  final productMap = <int, Product>{for (final p in products) p.id: p};

  final inventoryMap = <int, InventoryItem>{};
  for (final item in items) {
    final inv = await db.getInventoryItemByProductId(item.productId);
    if (inv != null) inventoryMap[item.productId] = inv;
  }

  if (!context.mounted) return;

  // 顯示 ShipOrderDialog（取代原本 AlertDialog）
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => ShipOrderDialog(
      order: order,
      items: items,
      productMap: productMap,
      inventoryMap: inventoryMap,
    ),
  );

  if (confirmed != true) return;

  final now = DateTime.now().toUtc();

  // 本地樂觀更新 + enqueue（邏輯不變）
  await db.updateSalesOrderStatus(order.id, 'shipped', shippedAt: now);
  await sync.enqueueUpdate('sales_order', order.id, {
    'id': order.id, 'status': 'shipped',
    'shippedAt': now.toIso8601String(), 'updatedAt': now.toIso8601String(),
  });
  for (final item in items) {
    await sync.enqueueDeltaUpdate('inventory_delta', 'out', {
      'productId': item.productId, 'amount': item.quantity,
    });
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('出貨完成，庫存扣除已排入待同步佇列')),
    );
  }
}
```

### 2-2. import 補充

```dart
import 'ship_order_dialog.dart';  // 新增
// inventory_items_dao.dart + product_dao.dart 已在 Phase #12 後加入
```

---

## Phase 3：驗收

### 3-1. 靜態分析

```
dart analyze lib/features/sales_orders/sales_order_list_screen.dart \
             lib/features/sales_orders/ship_order_dialog.dart
```

預期：0 issues

### 3-2. UI 驗收（行為矩陣）

| 情境 | 操作 | 預期行為 |
|------|------|----------|
| confirmed 訂單，warehouse 角色 | 點「出貨」| ShipOrderDialog 顯示明細 + 庫存快照 |
| 已 reserve（reserved >= qty）| ShipOrderDialog | 顯示出貨後 onHand / reserved，無警示 |
| 未 reserve（reserved < qty）| ShipOrderDialog | ⚠️ 橘色警示「尚未預留，服務端將拒絕」|
| onHand < qty | ShipOrderDialog | 🔴 紅色警示「在庫不足」|
| ShipOrderDialog 取消 | — | 無 enqueue，status 不變 |
| ShipOrderDialog 確認 | — | status=shipped，enqueue out × N，SnackBar |

### 3-3. curl 驗收

```bash
# 前置：reserve 後再 out（正常流程）
POST /push  inventory_delta:reserve amount=N  → 200 succeeded
POST /push  inventory_delta:out    amount=N  → 200 succeeded
GET  /pull  inventory_delta                  → onHand-=N, reserved-=N ✅

# 未 reserve 直接 out（警示情境）
POST /push  inventory_delta:out    amount=N  → 409 INSUFFICIENT_STOCK
GET  /pull                                   → Force Pull，狀態一致 ✅
```

---

## 依賴關係

```
Phase 1（ShipOrderDialog 新增）←── 可先完成
       ↓
Phase 2（_shipOrder() 更新）
       ↓
Phase 3（dart analyze + UI + curl 驗收）
```

---

## 影響評估

| 現有功能 | 影響 |
|---------|:----:|
| `_confirmOrder()`（status 更新）| 不變 |
| `_reserveInventory()`（reserve delta）| 不變 |
| `_cancelOrder()`（cancel delta）| 不變 |
| 後端 `out` 邏輯（onHand / reserved 雙扣）| 不變，已驗收 |
| Race Condition（409 + Force Pull）| 不變 |
| `InventoryListScreen`（庫存快照）| 不變 |
