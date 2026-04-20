# UI 調整記錄 — 2026-04-20

---

## 1. 雙語切換功能（Route B：AppStrings ChangeNotifier）

### 新增檔案
- `packages/frontend/lib/core/app_strings.dart`
  - `AppStrings extends ChangeNotifier`，涵蓋全部 16 個畫面的中英文字串
  - `setEnglish(bool)` 觸發全 App rebuild
  - `static AppStrings of(BuildContext context)` 快捷存取

### 修改檔案
- `packages/frontend/lib/main.dart`
  - 加入 `ChangeNotifierProvider<AppStrings>`
  - 移除 `static const _titles`，改為 `build()` 內動態取得
  - NavigationBar labels、FAB tooltips、AppBar sync tooltip、登出對話框全部接 `AppStrings`
- `packages/frontend/lib/features/settings/dev_settings_screen.dart`
  - 頂部新增 `SwitchListTile`（English UI 開關）
  - AppBar title 改用 `s.devTitle`

### 操作方式
開發者設定 → 最上方 **English UI** 開關 → 即時切換，無需重啟

---

## 2. NavigationBar 英文標籤縮短

避免 6 個標籤在小螢幕上斷行，調整 `app_strings.dart` 的 `navXxx` getter：

| 原本 | 改為 |
|------|------|
| Dashboard | Home |
| Customers | Clients |
| Products | Products（不變）|
| Quotations | Quotes |
| Orders | Orders（不變）|
| Inventory | Stock |

---

## 3. 報價 / 訂單按鈕列改為 Wrap

- 問題：按鈕過多時 `Row` 超出螢幕邊緣
- 修正：`quotation_list_screen.dart` 與 `sales_order_list_screen.dart` 的操作按鈕 `Row` 改為 `Wrap(alignment: WrapAlignment.end)`
- 效果：空間不足時按鈕自動換行，不再溢出

---

## 4. 刪除 / 取消訂單改為選取模式保護

### 問題
「刪除」（報價）、「取消」（訂單）按鈕直接暴露在卡片上，容易誤觸。

### 設計
- 移除卡片上的「刪除」/「取消」按鈕
- **長按**任一可操作卡片進入選取模式
- 頂部出現藍色工具列：已選取數量 ＋ 確認操作 ＋ ✕ 離開
- 卡片左側出現 Checkbox，單點切換勾選
- 選取模式下，PDF / 寄信 / 業務操作按鈕全部隱藏

### 保護規則
| 畫面 | 不可選取的項目 |
|------|--------------|
| 報價 | `converted`（已轉訂）的報價 |
| 訂單 | `shipped`（已出貨）、離線（id < 0）的訂單 |

### 批次處理邏輯
- **報價刪除**：軟刪除（`deleted_at` 設為現在）+ `enqueueDelete` 等待同步
- **訂單取消**：`status → cancelled` + `enqueueUpdate`；若原為 `confirmed` 自動補排 `cancel delta` 釋放庫存預留

### 修改檔案
- `packages/frontend/lib/features/quotations/quotation_list_screen.dart`
- `packages/frontend/lib/features/sales_orders/sales_order_list_screen.dart`