# ADR-006：AppBar Badge 視覺一致性修正

**日期**：2026-05-26  
**狀態**：已採用  
**決策者**：Phase 4 UI 設計審查

---

## 背景

HomeScreen AppBar 有兩個 Badge：

- **異常通知鈴鐺**（`_AnomalyBell`）：`isLabelVisible: urgentCount > 0`
- **同步狀態按鈕**：`isLabelVisible: pending > 1`

兩者共用相同常數（`largeSize: 10.0`、`padding: EdgeInsets.zero`），但在相同數值下肉眼可見尺寸差異。根本原因有二：

1. **觸發條件不對稱**：`pending = 1` 時同步按鈕顯示 Flutter 預設 6px 小點，鈴鐺顯示 10px 圓圈，差距 40%。
2. **`smallSize` 未明確設定**：未設定時 Flutter Material 3 預設 `smallSize = 6.0`，當 `isLabelVisible: false` 時顯示 6px 小點而非完全隱藏。

---

## 決策

兩個 Badge 均採以下修正：

1. **統一 `isLabelVisible` 條件**：同步按鈕改為 `pending > 0`，與鈴鐺邏輯對齊（均為「有資料就顯示帶數字圓圈」）。
2. **明確設定 `smallSize: 0`**：完全關閉小點模式，確保只有「顯示帶數字圓圈」或「完全隱藏」兩種狀態，消除 6px vs 10px 的中間態。

```dart
// 同步按鈕（修正後）
Badge(
  isLabelVisible: pending > 0,   // 改：與鈴鐺條件對齊
  smallSize: 0,                  // 加：關閉小點模式
  largeSize: _appBarBadgeLargeSize,
  ...
)

// 鈴鐺（修正後）
Badge(
  isLabelVisible: urgentCount > 0,
  smallSize: 0,                  // 加：關閉小點模式
  largeSize: _appBarBadgeLargeSize,
  ...
)
```

---

## 理由

- 兩個 Badge 視覺行為完全一致，消除尺寸落差
- `pending = 1` 時顯示帶數字圓圈，語意更清晰（「有 1 筆 pending 也值得告知使用者」）
- `smallSize: 0` 讓狀態轉換更乾淨，無中間態小點閃爍

---

## 後果

**正面**
- 視覺一致性問題根本解決
- 狀態只有「顯示」與「隱藏」兩態，UI 行為可預期

**負面 / 注意**
- 同步按鈕在 `pending = 1` 時從「不顯示 Badge」改為「顯示帶數字圓圈」，屬行為變更，需 QA 驗收

---

## 相關文件

- `LOG/PHASE4-daily/2026-05-26 UI 設計決策記錄.md`（ADR-001 原始分析）
- `packages/frontend/lib/main.dart`（`_HomeScreenState.build` 同步按鈕；`_AnomalyBell`）
