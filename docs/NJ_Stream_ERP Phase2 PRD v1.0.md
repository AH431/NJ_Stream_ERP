# NJ_Stream_ERP Phase 2 PRD v1.0
**智慧可視化 · 異常預警 · CRM 強化 · 會計基礎**
**版本**：Phase 2 v1.0（2026-04-24）
**前置版本**：MVP v0.8（業務閉環已完成）

---

## 1. 背景與目標

### 1.1 現況（Phase 1 完成狀態）

| 模組 | 完成狀態 |
|------|---------|
| 客戶 / 產品管理 | ✅ CRUD + 雙語 + 離線同步 |
| 報價 → 訂單 → 出貨 業務閉環 | ✅ 全鏈路實機驗收 |
| 庫存管理（reserve / out / in） | ✅ Race condition 驗收通過 |
| CSV 批次匯入 | ✅ dart:io 重設計，Sony XA1 穩定 |
| PDF 匯出（報價單 / 訂單 / 對帳單）| ✅ 雙語 + 灰階四區塊設計 |
| 雙語 UI（14 個畫面）| ✅ AppStrings ChangeNotifier |
| 離線同步協定 v1.6 | ✅ LWW + ID chain + INSUFFICIENT_STOCK 409 |

### 1.2 Phase 2 目標

> **「讓數據說話：從操作工具升級為決策支援系統。」**

1. 將靜態數字轉換為可互動圖表，讓管理者一眼掌握業務狀態
2. 自動偵測業務異常，主動預警而非被動查詢
3. 強化客戶關係管理，從「記錄客戶」進化到「了解客戶」
4. 建立應收帳款與損益基礎，為後續完整會計功能鋪路

### 1.3 目標用戶擴展

| 角色 | Phase 1 主要用途 | Phase 2 新增用途 |
|------|-----------------|----------------|
| Sales（業務）| 建報價、轉訂單 | 看客戶健康度、接收流失預警 |
| Warehouse（倉管）| 入出庫操作 | 看庫存趨勢、接收缺貨預警 |
| Admin（管理者）| 全功能 | 看儀表板圖表、審閱異常清單、查損益 |

---

## 2. 功能範圍

### 模組總覽

```
Phase 2
├── P2-VIS   視覺化儀表板升級
├── P2-ALT   異常偵測引擎
├── P2-CRM   CRM 客戶健康度面板
└── P2-ACC   會計基礎（AR + 損益摘要）
```

---

## 3. P2-VIS：視覺化儀表板升級

### 3.1 技術選型

- **套件**：`fl_chart ^0.69`（Flutter，MIT 授權，無需額外 license）
- **資料來源**：新增後端聚合 API `/api/v1/analytics/...`，計算交給 PostgreSQL
- **快取策略**：分析資料允許 15 分鐘快取（不需要即時，減少同步負擔）
- **離線降級**：無網路時顯示「上次更新：N 分鐘前」，圖表仍可查看快取數據

### 3.2 儀表板佈局重設計

```
┌─────────────────────────────────────┐
│  KPI 卡片列（4 格）                  │  ← 保留現有，數字加趨勢箭頭
│  本月營收 / 訂單數 / 出貨數 / 待確認  │
├─────────────────────────────────────┤
│  月度營收折線圖（近 6 個月）          │  ← 新增
├──────────────┬──────────────────────┤
│  訂單狀態    │  產品銷售排行（Top 5） │  ← 新增
│  環形圖      │  水平長條圖            │
├──────────────┴──────────────────────┤
│  異常預警摘要（來自 P2-ALT）          │  ← 新增，可點擊跳轉
├─────────────────────────────────────┤
│  低庫存警示列表（現有）               │  ← 保留
└─────────────────────────────────────┘
```

### 3.3 圖表規格

#### 3.3.1 月度營收折線圖

| 項目 | 規格 |
|------|------|
| 資料範圍 | 近 6 個月，按月聚合 |
| X 軸 | 月份標籤（1月/Jan）|
| Y 軸 | 金額（千元為單位，自動縮放）|
| 互動 | 長按顯示該月詳細數字 Tooltip |
| 後端 API | `GET /api/v1/analytics/revenue?months=6` |
| 聚合邏輯 | `SUM(sales_orders.total_amount) WHERE status IN ('confirmed','shipped') GROUP BY month` |

#### 3.3.2 訂單狀態環形圖

| 項目 | 規格 |
|------|------|
| 資料 | 當月 pending / confirmed / shipped / cancelled 各筆數 |
| 顏色 | 與現有 status chip 色系一致（灰/藍/綠/紅）|
| 中心標籤 | 總訂單數 |
| 後端 API | `GET /api/v1/analytics/orders/status-summary` |

#### 3.3.3 產品銷售排行（Top 5）

| 項目 | 規格 |
|------|------|
| 資料 | 近 30 天，以出貨數量排名 |
| 圖表 | 水平長條圖，右側顯示數量 |
| 互動 | 點擊跳轉至該產品詳情 |
| 後端 API | `GET /api/v1/analytics/products/top-sales?days=30&limit=5` |

#### 3.3.4 客戶 × 月份 下單熱力圖矩陣（CRM 頁）

| 項目 | 規格 |
|------|------|
| 位置 | CRM 客戶列表頁頂部，可摺疊 |
| 資料 | 近 6 個月 × Top 10 客戶，格子顏色深淺代表訂單金額 |
| 互動 | 點擊格子跳轉該客戶該月訂單篩選 |
| 後端 API | `GET /api/v1/analytics/customers/heatmap?months=6&limit=10` |

#### 3.3.5 報價轉換漏斗圖（報價列表頁）

| 項目 | 規格 |
|------|------|
| 節點 | 建立報價 → 轉為訂單 → 確認訂單 → 已出貨 |
| 數字 | 各節點數量 + 轉換率（%）|
| 後端 API | `GET /api/v1/analytics/funnel?days=30` |

### 3.4 後端聚合 API 清單

| 路徑 | 說明 | 所需角色 |
|------|------|---------|
| `GET /analytics/revenue` | 月度營收 | admin, sales |
| `GET /analytics/orders/status-summary` | 訂單狀態分佈 | admin, sales |
| `GET /analytics/products/top-sales` | 產品銷售排行 | admin, warehouse |
| `GET /analytics/customers/heatmap` | 客戶下單熱力圖 | admin, sales |
| `GET /analytics/funnel` | 報價轉換漏斗 | admin, sales |
| `GET /analytics/inventory/trend` | 庫存變化趨勢 | admin, warehouse |

---

## 4. P2-ALT：異常偵測引擎

### 4.1 架構設計

```
後端定時掃描（Node.js cron job，每小時）
  ↓
AnomalyScanner.scan()
  ↓
寫入 anomalies 表（entityType / entityId / alertType / severity / message / resolvedAt）
  ↓
前端 Pull 時一併拉取未解決異常
  ↓
通知中心 UI（NotificationScreen）+ 儀表板摘要 Banner
```

### 4.2 異常規則清單

#### 4.2.1 訂單異常

| Alert Type | 觸發條件 | 嚴重度 | 說明 |
|-----------|---------|--------|------|
| `DUPLICATE_ORDER` | 同客戶 × 同品項，24h 內 ≥ 2 筆 pending | 🟡 medium | 可能誤按或重複下單 |
| `ORDER_QUANTITY_SPIKE` | 某品項本週訂購量 > 近 4 週週均值 × 3 | 🟡 medium | 採購量劇烈波動 |
| `CUSTOMER_INACTIVE` | 活躍客戶（90天內曾下單）超過 60 天無任何報價或訂單 | 🟠 high | 客戶流失預警 |
| `LARGE_ORDER_ANOMALY` | 單筆訂單金額 > 該客戶歷史均值 × 5 | 🟡 medium | 異常大單，需人工確認 |
| `LONG_PENDING_ORDER` | 訂單 status = pending 超過 14 天未確認 | 🟡 medium | 訂單停滯 |

#### 4.2.2 庫存異常

| Alert Type | 觸發條件 | 嚴重度 | 說明 |
|-----------|---------|--------|------|
| `STOCKOUT_PROLONGED` | `onHand - reserved < minStockLevel` 持續 ≥ 7 天 | 🔴 critical | 長期缺貨 |
| `DEAD_STOCK` | onHand > 0，但 90 天內出貨數量 = 0 | 🟡 medium | 呆滯庫存，佔用資金 |
| `STOCK_DEPLETION_ACCELERATING` | 近 7 天消耗速率 > 近 30 天均值 × 2 | 🟠 high | 庫存消耗加速，可能即將缺貨 |
| `NEGATIVE_AVAILABLE` | `onHand - reserved < 0`（資料異常）| 🔴 critical | 資料一致性問題 |

#### 4.2.3 客戶異常（CRM）

| Alert Type | 觸發條件 | 嚴重度 | 說明 |
|-----------|---------|--------|------|
| `HIGH_VALUE_CUSTOMER_CHURN_RISK` | LTV 前 20% 客戶，60 天靜默 | 🔴 critical | 高價值客戶流失風險 |
| `FREQUENT_CANCELLATION` | 同客戶近 30 天取消率 > 50% | 🟠 high | 需主動聯繫了解原因 |

### 4.3 資料庫 Schema

```sql
CREATE TABLE anomalies (
  id           SERIAL PRIMARY KEY,
  alert_type   VARCHAR(64) NOT NULL,
  severity     VARCHAR(16) NOT NULL,         -- critical / high / medium / low
  entity_type  VARCHAR(32) NOT NULL,         -- customer / product / sales_order / inventory_item
  entity_id    INTEGER NOT NULL,
  message      TEXT NOT NULL,               -- 人類可讀說明（中文）
  detail       JSONB,                       -- 數值依據（觸發時的快照）
  is_resolved  BOOLEAN DEFAULT FALSE,
  resolved_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_anomalies_unresolved ON anomalies (is_resolved, severity) WHERE is_resolved = FALSE;
```

### 4.4 前端 UI：通知中心（NotificationScreen）

```
通知中心
├── 篩選列（全部 / Critical / High / Medium）
├── 依嚴重度排序的 Alert 卡片列表
│   ├── 圖示（顏色代表嚴重度）
│   ├── 標題（Alert Type 轉中文）
│   ├── 說明文字（message）
│   ├── 關聯實體按鈕（跳轉至客戶 / 產品 / 訂單）
│   └── 「標記已解決」按鈕
└── 儀表板 Banner（僅顯示 critical 數量）
```

NavigationBar 新增「通知」Tab（`Icons.notifications_outlined`），有未解決 critical 時顯示紅色 Badge。

### 4.5 同步整合

- 異常記錄透過現有 `GET /sync/pull` 一併拉取（新增 `anomaly` entityType）
- 「標記已解決」透過現有 sync push 機制同步（operationType: `update`）
- Anomaly Scanner 為純後端 cron job，不需前端觸發

---

## 5. P2-CRM：客戶健康度面板

### 5.1 RFM 評分（伺服器端計算）

| 維度 | 說明 | 計算來源 |
|------|------|---------|
| **R**ecency | 距最後訂單天數（越小越好）| `sales_orders.created_at` |
| **F**requency | 近 90 天訂單筆數 | `sales_orders` count |
| **M**onetary | 近 90 天總金額 | `SUM(sales_orders.total_amount)` |

RFM 各維度分為 1–5 分，合計 3–15 分，對應客戶分級：

| 分數範圍 | 分級 | 顏色 | 建議動作 |
|---------|------|------|---------|
| 12–15 | 🌟 VIP | 金色 | 定期維繫 |
| 9–11 | 💚 活躍 | 綠色 | 持續跟進 |
| 6–8 | 🟡 觀察 | 黃色 | 主動關懷 |
| 3–5 | 🔴 流失風險 | 紅色 | 立即聯繫 |

### 5.2 客戶詳情頁強化

現有客戶詳情頁新增以下區塊：

```
客戶詳情頁（強化版）
├── 基本資料（現有）
├── ─────────────────
├── 健康度面板（新增）
│   ├── RFM 分級標籤
│   ├── 三維度數值（R: N天 / F: N筆 / M: $NNN）
│   ├── 總訂單金額 LTV
│   └── 平均訂單週期（天）
├── ─────────────────
├── 互動記錄（新增）
│   ├── 時間軸列表（備註 + 時間戳）
│   └── 新增備註（FAB）
├── ─────────────────
├── 近期訂單（近 5 筆，可展開）
└── 異常標記（來自 P2-ALT，若有）
```

### 5.3 互動記錄（CustomerInteractions）

```sql
CREATE TABLE customer_interactions (
  id           SERIAL PRIMARY KEY,
  customer_id  INTEGER NOT NULL REFERENCES customers(id),
  note         TEXT NOT NULL,
  created_by   INTEGER REFERENCES users(id),
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
```

- 僅支援新增與刪除（不需編輯，保留稽核軌跡）
- 透過現有 sync 機制同步（operationType: `create` / `delete`）
- 離線時寫入本地，排入 pending_operations

### 5.4 客戶列表強化

| 強化項目 | 說明 |
|---------|------|
| RFM 分級標籤 | 列表每筆客戶右側顯示分級顏色 |
| 排序選項 | 依 RFM 分數、最後訂單日、LTV 排序 |
| 篩選選項 | 僅顯示「流失風險」客戶 |
| 客戶 × 月份熱力圖 | 列表頁頂部可摺疊（見 P2-VIS 3.3.4）|

---

## 6. P2-ACC：會計基礎

> **範圍限定**：本階段不實作複式記帳，僅建立應收帳款追蹤與月度損益摘要。

### 6.1 應收帳款（Accounts Receivable）

#### 6.1.1 AR 狀態流程

```
出貨（shipped）→ 待收款（unpaid）→ 已收款（paid）→ 已沖銷（written_off）
```

#### 6.1.2 資料庫欄位（擴充 sales_orders）

```sql
ALTER TABLE sales_orders ADD COLUMN payment_status VARCHAR(16) DEFAULT 'unpaid';
-- unpaid / paid / written_off
ALTER TABLE sales_orders ADD COLUMN paid_at TIMESTAMPTZ;
ALTER TABLE sales_orders ADD COLUMN due_date DATE;  -- 到期日（出貨日 + 付款條件天數）
```

#### 6.1.3 AR Aging 矩陣

位置：新增「應收帳款」頁面（Admin 限定）

```
應收帳款頁
├── 總覽卡片（未收金額 / 逾期金額 / 本月已收）
├── ─────────────────
├── AR Aging 矩陣
│   ├── 0–30 天（正常）
│   ├── 31–60 天（注意）
│   ├── 61–90 天（警示）
│   └── 90+ 天（逾期）
│   各欄顯示：筆數 + 金額 + 佔比長條
├── ─────────────────
└── 逾期帳款明細列表（可按「標記已收款」）
```

#### 6.1.4 付款條件設定

- 客戶資料新增 `payment_terms_days` 欄位（預設 30 天）
- 出貨後自動計算 `due_date = shipped_at + payment_terms_days`
- 逾期自動產生 `OVERDUE_PAYMENT` Anomaly（嚴重度 high）

### 6.2 月度損益摘要

> **注意**：需先在產品資料補充 `cost_price` 欄位才能計算毛利。

| 項目 | 計算來源 |
|------|---------|
| 收入 | `SUM(total_amount) WHERE status = 'shipped'` |
| 銷售成本（COGS）| `SUM(qty × cost_price)` 依出貨明細 |
| 毛利 | 收入 - COGS |
| 毛利率 | 毛利 / 收入 × 100% |

- 位置：儀表板頁底部（Admin 限定）或獨立「報表」Tab
- 呈現方式：月度折線圖（毛利率走勢）+ 當月數字卡片

---

## 7. 角色權限矩陣更新

| 功能 | Sales | Warehouse | Admin |
|------|-------|-----------|-------|
| 儀表板圖表（營收/訂單）| ✅ | 🚫 | ✅ |
| 儀表板圖表（庫存趨勢）| 🚫 | ✅ | ✅ |
| 通知中心（查看）| ✅ 僅客戶/訂單類 | ✅ 僅庫存類 | ✅ 全部 |
| 通知中心（標記已解決）| ✅ 自己權限範圍 | ✅ 自己權限範圍 | ✅ |
| 客戶健康度 / RFM | ✅ | 🚫 | ✅ |
| 互動記錄（新增）| ✅ | 🚫 | ✅ |
| 應收帳款 | 🚫 | 🚫 | ✅ |
| 損益摘要 | 🚫 | 🚫 | ✅ |

---

## 8. Schema Migration 計畫

| 版本 | 變更 | 影響 |
|------|------|------|
| v4 | 新增 `anomalies` 表 | 後端：build migration；前端：新增 DAO |
| v5 | 新增 `customer_interactions` 表 | 同步協定新增 entityType |
| v6 | `sales_orders` 加 `payment_status / paid_at / due_date` | Migration script + `addColumn` |
| v7 | `products` 加 `cost_price` | Migration + ProductFormScreen 新增欄位 |
| v8 | `customers` 加 `payment_terms_days / rfm_score` | RFM 可由後端計算寫回 |

---

## 9. 推進順序與工作拆解

### Sprint A（視覺化 + 異常引擎骨架）— 預計 1.5 週

| # | 任務 | 模組 |
|---|------|------|
| A1 | 後端 analytics 聚合 API（5 支）| P2-VIS |
| A2 | `fl_chart` 整合，儀表板折線圖 + 環形圖 + 排行榜 | P2-VIS |
| A3 | 後端 `anomalies` 表 + AnomalyScanner cron job | P2-ALT |
| A4 | 前端通知中心 UI + NavigationBar Badge | P2-ALT |
| A5 | Sync pull 整合 anomaly entityType | P2-ALT |

### Sprint B（CRM 強化）— 預計 1 週

| # | 任務 | 模組 |
|---|------|------|
| B1 | 後端 RFM 計算 API + `customer_interactions` 表 | P2-CRM |
| B2 | 客戶詳情頁健康度面板 | P2-CRM |
| B3 | 互動記錄（新增 / 刪除 / 同步）| P2-CRM |
| B4 | 客戶列表 RFM 標籤 + 篩選排序 | P2-CRM |
| B5 | 客戶 × 月份熱力圖矩陣 | P2-CRM + P2-VIS |

### Sprint C（會計基礎）— 預計 1 週

| # | 任務 | 模組 |
|---|------|------|
| C1 | `products.cost_price` 欄位 + ProductFormScreen | P2-ACC |
| C2 | `sales_orders` AR 欄位 migration + 業務邏輯 | P2-ACC |
| C3 | 應收帳款頁（AR Aging 矩陣）| P2-ACC |
| C4 | 月度損益摘要（儀表板 + 折線圖）| P2-ACC |
| C5 | 逾期自動產生 Anomaly | P2-ALT + P2-ACC |

---

## 10. 技術決策記錄

| 決策 | 選項 | 理由 |
|------|------|------|
| 圖表套件 | `fl_chart` | MIT 授權、活躍維護、Flutter 生態最主流 |
| 分析資料計算位置 | PostgreSQL（後端聚合）| 避免前端處理大量原始資料；離線時可用快取 |
| 異常偵測觸發方式 | 後端 cron job（每小時）| 不依賴前端在線；電池友好 |
| RFM 計算位置 | 後端計算寫回 DB | 多裝置一致；前端只讀取已計算結果 |
| 複式記帳 | 不在本 Phase 範圍 | 工程量過大；先建立 AR 追蹤驗證需求真實性 |
| AR 觸發 Anomaly | shipped 後 N 天自動觸發 | 與 AnomalyScanner 共用架構，不新增機制 |

---

## 11. 驗收標準

| 模組 | 驗收條件 |
|------|---------|
| P2-VIS | 儀表板圖表正確渲染且數字與資料庫一致；離線狀態顯示快取並有時間戳提示 |
| P2-ALT | 異常正確觸發（含邊界條件）；標記已解決後多裝置同步消失；Badge 計數準確 |
| P2-CRM | RFM 分級與手算結果一致；互動記錄離線新增後同步成功；熱力圖顯示正確 |
| P2-ACC | AR Aging 分類與實際日期差吻合；「標記已收款」後狀態同步；損益數字可手動核對 |

---

*文件維護者：AH431 | 產品架構：NJ_Stream_ERP | 下一個版本：Phase 3 PRD（待定，預計含多倉庫支援、完整採購模組）*
