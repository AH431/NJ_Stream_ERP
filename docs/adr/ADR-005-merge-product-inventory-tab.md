# ADR-005：合併 Product Tab 與 Inventory Tab 為「庫存＆商品」Tab

**日期**：2026-05-26  
**狀態**：已採用  
**決策者**：Phase 4 UI 設計審查

---

## 背景

底部 NavigationBar 原有 6 個 Tab（Dashboard / 客戶 / 產品 / 報價 / 訂單 / 庫存）。為在不超過 6 個 Tab 的前提下加入 AI Assistant Tab（ADR-004），需合併一組相關功能。

Sales 角色在日常工作中同時需要查詢庫存數量與商品售價規格，現有設計要求在兩個 Tab 之間來回切換。

---

## 決策

**合併 Product Tab（原索引 2）與 Inventory Tab（原索引 5）為單一「庫存＆商品」Tab（新索引 4）**，以 Inventory 為主視圖格式，附加產品規格與售價資訊。底部 Tab 從 6 個縮減為 5 個功能 Tab + 1 個 AI Tab。

### 新 Tab 結構

```
Dashboard | 客戶 | 報價 | 訂單 | 庫存＆商品 | AI 助理
  (0)       (1)   (2)   (3)      (4)          (5)
```

### Tab 標籤規格

| 語言 | Tab 標籤 | AppBar 子標題 |
|------|---------|--------------|
| 繁中 | 庫存＆商品 | 規格 / 售價 / 庫存數量 |
| 英文 | Products | Specs / Prices / Stock Qty |

英文 Tab 標籤採用「Products」（不用 Stock / Inventory），反映本 Tab 同時涵蓋商品規格與庫存資訊。

---

## 入庫操作流程變更

| | 舊流程 | 新流程 |
|--|--------|--------|
| 觸發點 | 庫存 Tab → FAB 直接開 StockInDialog | 庫存＆商品 Tab → 點擊商品列 → 商品詳情頁 → 入庫操作 |
| 優點 | 步驟少 | 入庫有明確商品上下文，避免 Dialog 內重複選商品 |

StockIn FAB 已從 main.dart 移除；商品詳情頁入口為後續 Sprint 實作項目。

---

## 角色 FAB 對應

| 角色 | Tab 4（庫存＆商品）FAB |
|------|----------------------|
| Admin | 新增品項（`ProductFormScreen`）|
| Sales | 無 |
| Warehouse | 無（入庫改由詳情頁觸發）|

---

## 理由

- Sales 查詢售價與庫存不再切換 Tab，工作流程更順暢
- Tab 總數維持 6 個，視覺不擁擠
- 合併後 `IndexedStack` 子 Widget 從 6 個降至 6 個（5 功能 + AI），記憶體佔用不變

---

## 後果

**正面**
- Sales 查詢售價 + 庫存一站式完成
- 入庫操作有商品上下文，操作意圖更明確

**負面 / 注意**
- Warehouse 角色的 StockIn FAB 已移除；商品詳情頁尚未實作，目前無法從 UI 觸發入庫——需後續 Sprint 補完
- `sales_order_list_screen.dart` 的 `requestTabSwitch(3)` 已更新為 `requestTabSwitch(2)`（報價 Tab 從索引 3 移至 2）

---

## 相關文件

- `ADR-004-ai-tab-bottom-nav.md`
- `LOG/PHASE4-daily/2026-05-26 UI 設計決策記錄.md`（ADR-004 原始分析）
- `packages/frontend/lib/main.dart`（Tab 結構與 FAB 邏輯）
- `packages/frontend/lib/core/app_strings.dart`（`navInventory`、`titleInventory`、`navAiChat`、`titleAiChat`）
- `packages/frontend/lib/features/sales_orders/sales_order_list_screen.dart`（tab 索引修正）
