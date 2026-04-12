# Issue #8 Task List — 報價單 UI（稅額切換 + Decimal）

**Milestone**：W5 CRM  
**Agent**：B（前端）  
**前置**：#7（First-to-Sync wins 後端）已完成

---

## 範疇說明

| 功能 | 本 Issue |
|------|:--------:|
| QuotationDao（CRUD + LWW upsert）| ✅ |
| SyncProvider：pull 補完 quotation + salesOrder | ✅ |
| QuotationListScreen（列表 + 軟刪除 + 轉訂單）| ✅ |
| QuotationFormScreen（新增、稅額切換、Decimal 計算）| ✅ |
| HomeScreen 加第三 tab（報價）| ✅ |
| SalesOrderDao（轉訂單後 upsert）| ✅ 最小範疇 |
| 報價編輯 / 訂單列表 UI | ❌ 留後續 |

---

## 稅額邏輯（強制規範）

- `subtotalSum` = Σ ( `quantity` × `unitPrice` )，全部以 `Decimal` 計算
- `taxAmount` = `subtotalSum × Decimal('0.05')` 若含稅；否則 `Decimal.zero`
- `totalAmount` = `subtotalSum + taxAmount`
- 所有金額存 DB 前呼叫 `.toStringAsFixed(2)` → `"200.00"` 格式
- **禁止** 任何 `double` 運算參與金額計算

---

## Phase 1：QuotationItemModel + QuotationDao

**新增檔案**：`lib/database/dao/quotation_dao.dart`

### 1-1 QuotationItemModel（本地 helper，不進 Drift schema）

```dart
class QuotationItemModel {
  final int productId;
  final int quantity;
  final String unitPrice;  // "100.00"
  final String subtotal;   // "200.00"

  // fromJson(Map) / toJson() / toJsonString() / fromJsonString(String)
}
```

- [ ] 實作 `fromJson` / `toJson` / `fromJsonString` / `toJsonString`

### 1-2 QuotationDao（AppDatabase extension）

- [ ] `watchActiveQuotations()` → `Stream<List<Quotation>>`（`deleted_at IS NULL`，`updatedAt` 降序）
- [ ] `insertQuotation(QuotationsCompanion)` → 離線新增，id 為負數臨時 id
- [ ] `softDeleteQuotation(int id, DateTime deletedAt)` → 寫入 `deleted_at + updated_at`
- [ ] `upsertQuotationFromServer(QuotationsCompanion)` → LWW（同 `CustomerDao.upsertCustomerFromServer`，以 `updatedAt` 判斷）
- [ ] `clearOrphanedOfflineQuotations(List<String> pendingRelatedIds)` → 清除 `id < 0` 的孤兒

---

## Phase 2：SalesOrderDao（最小範疇）

**新增檔案**：`lib/database/dao/sales_order_dao.dart`

只需「轉訂單」後能 upsert 本地記錄、以及 Force Overwrite 時可以寫入。

- [ ] `insertSalesOrder(SalesOrdersCompanion)` → 離線新增（id 為負數）
- [ ] `upsertSalesOrderFromServer(SalesOrdersCompanion)` → LWW upsert

---

## Phase 3：SyncProvider 補完

**修改**：`lib/providers/sync_provider.dart`

### 3-1 pullData() — 補 quotation + sales_order

- [ ] 在 `queryParameters` 的 `entityTypes` 改為 `'customer,product,quotation,sales_order'`
- [ ] 解析 `data['quotations']` → 呼叫 `_applyForceOverwrite('quotation', ...)`
- [ ] 解析 `data['salesOrders']` → 呼叫 `_applyForceOverwrite('sales_order', ...)`
- [ ] 在 orphan 清除區塊補上 `clearOrphanedOfflineQuotations(relatedIds)`

### 3-2 _applyForceOverwrite — 補 quotation + sales_order

- [ ] 新增 `quotation` case：解析 `items` JSON → `QuotationsCompanion`，呼叫 `db.upsertQuotationFromServer`
- [ ] 新增 `sales_order` case：解析欄位 → `SalesOrdersCompanion`，呼叫 `db.upsertSalesOrderFromServer`

---

## Phase 4：QuotationListScreen

**新增檔案**：`lib/features/quotations/quotation_list_screen.dart`

- [ ] `StreamBuilder<List<Quotation>>` 監聽 `db.watchActiveQuotations()`
- [ ] 每列顯示：客戶名（從本地 Drift customers 查，id 比對）、`totalAmount`、狀態 Chip、離線同步 icon
- [ ] 狀態 Chip 顏色：draft（灰）、sent（藍）、converted（綠）、expired（橘）
- [ ] 軟刪除（只有 `sales / admin` 可操作，`converted` 狀態不可刪除）：AlertDialog 確認 → `db.softDeleteQuotation` + `sync.enqueueDelete`
- [ ] 「轉訂單」按鈕（`draft` / `sent` 且 `convertedToOrderId == null` 才顯示）：
  - 本地：`db.softUpdateQuotationStatus(id, 'converted')` 樂觀更新
  - enqueue：`sync.enqueueCreate('sales_order', payload)`（含 `quotationId`）
  - Snackbar 提示「轉訂單已排入待同步佇列」
  - 同步後 FORBIDDEN_OPERATION：`_handleError` 自動 Force Overwrite 本地報價

  > **注意**：樂觀更新 `status` 但 `convertedToOrderId` 暫時不填（後端配發後由 Pull 補齊），`id < 0` 的 salesOrder 記錄不顯示在任何列表。

- [ ] 客戶名查詢：用 `FutureBuilder` 或從 `customerMap` cache（一次查所有 customers，建立 Map<int, String>），不做逐筆 query

---

## Phase 5：QuotationFormScreen

**新增檔案**：`lib/features/quotations/quotation_form_screen.dart`

### 5-1 狀態管理

```dart
List<_ItemRow> _rows;   // 可動態增減
bool _withTax = true;   // 含稅切換
int? _selectedCustomerId;
```

### 5-2 客戶選擇

- [ ] `DropdownButtonFormField<int>`，選項來自 `FutureBuilder(db.getActiveCustomers())`
- [ ] validator：必選

### 5-3 明細行（`_ItemRow`）

每行：
- [ ] 產品下拉（`FutureBuilder(db.getActiveProducts())`，顯示 `name (SKU)`）
- [ ] 選定產品後自動帶入 `unitPrice`（從 Product Drift 記錄）
- [ ] 數量欄位（`TextEditingController`，整數，> 0）
- [ ] 單價欄位（`TextEditingController`，預填但可改，Decimal 格式驗證：`^\d+(\.\d{1,2})?$`）
- [ ] 小計欄位（**唯讀**，`= Decimal.parse(unitPrice) * Decimal.fromInt(quantity)`，onChange 即時更新）
- [ ] 刪除行按鈕（至少保留 1 行）

### 5-4 稅額切換

- [ ] `SwitchListTile`（含稅 / 未稅）
- [ ] 切換時即時重算：
  ```
  subtotalSum = Σ subtotal (Decimal)
  taxAmount   = withTax ? subtotalSum * Decimal('0.05') : Decimal.zero
  totalAmount = subtotalSum + taxAmount
  ```
- [ ] 金額摘要顯示區（固定在表單底部）：小計、稅額（標示 5%）、合計

### 5-5 儲存流程

- [ ] `_formKey.validate()` 通過後執行
- [ ] `localId = SyncProvider.nextLocalId()`
- [ ] 建立 `List<QuotationItemModel>`，將每行序列化為 `toJsonString()`
- [ ] `db.insertQuotation(QuotationsCompanion(..., items: Value(itemsJson), ...))`
- [ ] `sync.enqueueCreate('quotation', payload)` — payload 的 `items` 為 `List<Map>` 格式
- [ ] `Navigator.pop(context)` → QuotationListScreen StreamBuilder 自動刷新

---

## Phase 6：HomeScreen + main.dart 更新

**修改**：`lib/main.dart`

- [ ] `_titles` 增加 `'報價管理'`（index 2）
- [ ] `IndexedStack` 增加 `QuotationListScreen()`
- [ ] `NavigationBar` 增加第三個 destination（`Icons.receipt_long_outlined` / `receipt_long`）
- [ ] `_buildFab`：tab 2 且 `role == 'sales' || role == 'admin'` → FAB 開啟 `QuotationFormScreen`
- [ ] import 新增的 screen 檔案

---

## Phase 7：驗收

- [x] `dart analyze` 通過（無 error，via database.dart entry point）
- [x] 稅額切換驗算（`test/tax_calc_test.dart` 5/5 passed）：
  - 新增 1 行：product 單價 `100.00`，數量 2 → subtotal `200.00`
  - 含稅：taxAmount = `10.00`，totalAmount = `210.00`
  - 切換未稅：taxAmount = `0.00`，totalAmount = `200.00`
- [x] 儲存後 QuotationListScreen 即時顯示新報價（`watchActiveQuotations()` stream → StreamBuilder 自動刷新）
- [x] 軟刪除後報價從列表消失（`deleted_at IS NULL` filter in `watchActiveQuotations`）
- [x] 「轉訂單」後狀態顯示 `converted`（綠色），轉訂單按鈕隱藏（`canConvert` 條件）
- [x] push 後端 → First-to-Sync wins 正常運作（Issue #7 curl 驗收：FORBIDDEN_OPERATION + server_state Force Overwrite ✅）
