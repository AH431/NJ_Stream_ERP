# ADR-004：AI Assistant 入口移至底部 NavigationBar Tab

**日期**：2026-05-26  
**狀態**：已採用  
**決策者**：Phase 4 UI 設計審查

---

## 背景

AI Chat 功能（`ChatScreen`）原本埋在 AppBar 右上角的 `PopupMenuButton` 三點選單內，屬低頻次級入口。若 AI Assistant 是產品的核心賣點，現有布局無法有效傳達其重要性，使用者容易忽略此功能。

---

## 決策

**採用方案 B：底部 NavigationBar 第 6 個 Tab（索引 5）**，透過 ADR-005 合併 Product + Inventory Tab 騰出位置給 AI。

---

## 比較的方案

| 方案 | 布局位置 | 優點 | 缺點 |
|------|----------|------|------|
| A：AppBar 專屬圖示 | 鈴鐺旁新增圖示 | 改動最小，永遠可見 | AppBar 已有 3 個 action，略擁擠 |
| **B：底部 NavigationBar Tab** | AI 與核心功能並列 | 地位最高，與其他功能平起平坐 | 依賴 ADR-005 合併其他 Tab |
| C：固定懸浮聊天按鈕 | Stack 右下角 FAB | 跨所有 Tab 持續可見 | 遮擋頁面內容；與現有 FAB 混淆 |

方案 C 明確排除，原因：懸浮按鈕遮蔽頁面資料，並與「新增報價單」等現有 FAB 產生視覺與功能混淆。

---

## 理由

- AI 與 Dashboard、客戶、報價等核心功能並列，地位明確
- 不新增 AppBar 圖示，維持現有視覺密度
- 消除懸浮按鈕的遮蔽與混淆問題

---

## 實作細節

**Tab 索引**：5（最後位置）  
**圖示**：`chat_bubble_outline`（未選） / `chat_bubble`（選中）  
**Tab 標籤**：`'AI 助理'` / `'AI'`（英文版）  
**AppBar 子標題**：`'智能問答與分析'` / `'Intelligent Q&A'`

PopupMenuButton 的 AI Chat 項目同步移除。

---

## 後果

**正面**
- AI 入口可發現性大幅提升，符合產品定位
- 移除 PopupMenu 項目後，選單保持簡潔

**負面 / 注意**
- 依賴 ADR-005 完成 Product + Inventory 合併
- `IndexedStack`、`_buildFab`、tab 索引相關邏輯均需調整

---

## 相關文件

- `ADR-005-merge-product-inventory-tab.md`
- `LOG/PHASE4-daily/2026-05-26 UI 設計決策記錄.md`（ADR-003 原始分析）
- `packages/frontend/lib/main.dart`（實作）
