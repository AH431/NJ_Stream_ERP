# ADR-007：AppBar 主標題 + 副標題雙層結構

**日期**：2026-05-26  
**狀態**：已採用  
**決策者**：Phase 4 UI 設計審查

---

## 背景

`HomeScreen` 的 AppBar 標題（`s.titleXxx`）與底部 `NavigationBar` 的 Tab 標籤（`s.navXxx`）為兩套獨立的 i18n 字串。底部空間有限，短標籤是必要的；但 AppBar 單獨顯示短標題時，缺乏說明性，使用者不易快速理解當前頁面的功能範疇。

---

## 決策

採用**主標題 + 副標題雙層結構（方案 B+）**：

- **主標題**：`s.navXxx`（與底部 Tab 完全一致，短字串）
- **副標題**：`s.titleXxx`（功能範疇說明，重新定義語意）

`titleXxx` 字串從「名詞標題」改為「簡短功能說明句式」，不廢除。

```dart
title: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,   // 不撐高 AppBar
  children: [
    Text(
      titles[_selectedIndex],       // s.navXxx
      style: Theme.of(context).textTheme.titleSmall,    // 14sp
    ),
    Text(
      subtitles[_selectedIndex],    // s.titleXxx
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),                            // 11sp, 次要色
    ),
  ],
),
```

### 字串對照表

| Tab | `navXxx`（主標題） | `titleXxx`（副標題，新語意） |
|-----|------------------|------------------------------|
| 儀表板 | 儀表板 / Home | 銷售與庫存總覽 / Sales & inventory overview |
| 客戶 | 客戶 / Clients | 聯絡資訊與往來紀錄 / Contacts & transaction history |
| 報價 | 報價 / Quotes | 報價單管理 / Manage quotations |
| 訂單 | 訂單 / Orders | 銷售訂單追蹤 / Track sales orders |
| 庫存＆商品 | 庫存＆商品 / Products | 規格 / 售價 / 庫存數量 / Specs / Prices / Stock Qty |
| AI 助理 | AI 助理 / AI | 智能問答與分析 / Intelligent Q&A |

---

## 比較的方案

| 方案 | 說明 | 優點 | 缺點 |
|------|------|------|------|
| A：Nav 移除文字 | `label: ''`，AppBar 顯示完整標題 | 一致性最高 | 可發現性差，新使用者學習成本高 |
| B：合併為一套短字串 | AppBar 直接讀 `s.navXxx` | i18n 只維護一份 | AppBar 標題過短，缺乏說明性 |
| **B+：雙層結構（採用）** | 主標題短 + 副標題說明 | 一致性 + 說明性兼顧 | 字型略縮小以維持原 AppBar 高度 |
| C：onlyShowSelected | 未選中 Tab 隱藏 label | 視覺層次感好 | 兩套字串仍需維護，實作稍複雜 |

---

## 理由

- 底部 Tab 標籤與 AppBar 主標題 100% 一致，使用者切換 Tab 時方向感清晰
- 副標題補充功能說明，降低新使用者認知負擔
- `mainAxisSize: MainAxisSize.min` + `titleSmall`（14sp）+ `labelSmall`（11sp）確保雙層文字不撐高 AppBar 垂直高度
- `titleXxx` 字串組保留並賦予新語意，無需刪減 i18n 定義

---

## 後果

**正面**
- Tab 切換方向感清晰
- 新使用者認知負擔降低

**負面 / 注意**
- `titleXxx` 語意已從「主標題名詞」改為「功能說明句式」，若未來其他地方引用這批字串需留意語意變化
- 配合 ADR-005 Tab 結構重組後，`titles` 與 `subtitles` 陣列的索引已同步更新至新 Tab 排列

---

## 相關文件

- `LOG/PHASE4-daily/2026-05-26 UI 設計決策記錄.md`（ADR-002 原始分析）
- `packages/frontend/lib/main.dart`（`_HomeScreenState.build` AppBar title Column）
- `packages/frontend/lib/core/app_strings.dart`（`titleXxx` 字串更新）
