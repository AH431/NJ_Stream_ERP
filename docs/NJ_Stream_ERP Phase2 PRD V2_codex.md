# NJ_Stream_ERP Phase 2 PRD V2_codex
**決策支援系統升級版：Foundation 先行 + 模組分段落地**
**版本**：V2_codex（2026-04-24）
**基準文件**：`NJ_Stream_ERP Phase2 PRD v1.0.md`
**前置版本**：MVP v0.8（業務閉環已完成）

---

## 1. 文件定位

本文件不是推翻 v1.0，而是把 v1.0 重寫成「依照目前 repo 真實進度可執行」的版本。

核心調整：

1. 先補齊 `schema / sync / route / navigation / cache` 地基，再疊功能。
2. 先交付低風險、高可見度的分析圖表與最小異常偵測。
3. CRM 與會計基礎分段落地，避免一次牽動過多資料模型。
4. 排程從理想型功能切分，改為穩定性優先的實作切分。

---

## 2. 現況評估

### 2.1 已具備的 Phase 1 能力

| 能力 | 狀態 | 說明 |
|------|------|------|
| 客戶 / 產品 / 報價 / 訂單 / 庫存閉環 | ✅ | 已有可運作的核心流程 |
| 離線同步 | ✅ | 已有 LWW、ID remap、pending queue |
| 雙語 UI | ✅ | 已完成 14 個畫面遷移 |
| 本地資料庫 | ✅ | Drift schema 已運作並有升版流程 |
| PDF / Email / CSV import | ✅ | 已驗證可用 |

### 2.2 目前不存在但 Phase 2 需要的能力

| 項目 | 現況 | 影響 |
|------|------|------|
| `analytics` 路由與聚合 API | ❌ | 圖表無資料來源 |
| `anomalies` / `customer_interactions` schema | ❌ | ALT / CRM 無法落地 |
| `anomaly` / `customer_interaction` sync entity | ❌ | 多裝置一致性不足 |
| 通知中心 / AR / 報表導航入口 | ❌ | 前端資訊架構需調整 |
| `payment_status / due_date / cost_price / payment_terms_days` | ❌ | ACC 無法正確計算 |
| analytics 快取策略實作 | ❌ | 離線圖表體驗尚未建立 |

### 2.3 計畫原則

- **穩定性優先於功能數量**
- **先做只讀分析，再做可寫回流程**
- **先做最小可驗證規則，再擴大規則集合**
- **所有新功能必須明確對齊 sync contract 與 migration 計畫**

---

## 3. Phase 2 模組重排

```
Phase 2
├── P2-FND   Foundation（schema / sync / route / nav / cache）
├── P2-VIS   視覺化儀表板升級
├── P2-ALT   異常偵測引擎
├── P2-CRM   客戶健康度與互動記錄
└── P2-ACC   會計基礎（AR + 損益摘要）
```

### 3.1 新的實作順序

1. `P2-FND`
2. `P2-VIS`
3. `P2-ALT` 最小版
4. `P2-CRM`
5. `P2-ACC`

---

## 4. P2-FND：Foundation

> 這一階段不追求使用者可見的新功能，而是建立所有 Phase 2 功能的共同地基。

### 4.1 目標

1. 定義新的後端 / 前端 schema 與 migration 命名規則
2. 擴充 sync entityType 與 payload contract
3. 建立 analytics API 與快取資料模型
4. 規劃新的前端導航入口，不破壞既有 6-tab 主流程
5. 補齊 Phase 2 最低限度測試與驗收手冊

### 4.2 必做項目

| 項目 | 說明 |
|------|------|
| Migration 命名重整 | 舊 PRD 的 v4–v8 與目前前端 schemaVersion 會衝突，需改成獨立 Phase 2 migration 編號 |
| Sync Contract 擴充 | 新增 `anomaly`、`customer_interaction`，並定義 pull/push payload |
| Role matrix 落地 | API 與 UI 都要一致限制權限 |
| Navigation 擴充 | 通知、AR、報表入口改採可擴充設計，避免直接擠爆底部 tab |
| Cache 設計 | analytics 本地快取表或本地 JSON cache，需帶 `fetchedAt` |
| 驗收基線 | 每個模組都需有「手算比對」與「離線/多裝置驗證」步驟 |

### 4.3 輸出物

- `docs/api-contract-sync-v1.7.yaml` 或 Phase 2 addendum
- backend migrations
- frontend Drift schema migration
- analytics route skeleton
- updated navigation design note

---

## 5. P2-VIS：視覺化儀表板升級

### 5.1 範圍

本模組拆為兩波：

- **Wave 1（優先）**：營收折線圖、訂單狀態環形圖、Top 5 產品排行
- **Wave 2（延後）**：客戶熱力圖、報價漏斗、庫存趨勢

### 5.2 技術選型

- 套件：`fl_chart`
- 聚合位置：PostgreSQL + backend route
- 快取策略：15 分鐘
- 離線降級：顯示上次成功更新時間與快取資料

### 5.3 為何優先

1. 大部分資料已存在於現有訂單 / 訂單明細 / 庫存表
2. 以只讀 API 為主，不會先碰複雜同步寫回
3. 使用者可最快看到「系統升級」的感知價值

### 5.4 Wave 1 規格

| 功能 | API | 角色 |
|------|-----|------|
| 月度營收折線圖 | `GET /api/v1/analytics/revenue?months=6` | admin, sales |
| 訂單狀態環形圖 | `GET /api/v1/analytics/orders/status-summary` | admin, sales |
| Top 5 產品排行 | `GET /api/v1/analytics/products/top-sales?days=30&limit=5` | admin, warehouse |

### 5.5 Wave 2 規格

| 功能 | API | 角色 |
|------|-----|------|
| 客戶下單熱力圖 | `GET /api/v1/analytics/customers/heatmap?months=6&limit=10` | admin, sales |
| 報價轉換漏斗 | `GET /api/v1/analytics/funnel?days=30` | admin, sales |
| 庫存變化趨勢 | `GET /api/v1/analytics/inventory/trend` | admin, warehouse |

### 5.6 驗收標準

- 圖表數值與資料庫手算一致
- 無網路時可顯示最近一次快取資料
- 不影響現有 Dashboard refresh 與低庫存清單

---

## 6. P2-ALT：異常偵測引擎

### 6.1 落地策略

先做 **最小版規則集**，再擴充。

### 6.2 MVP 規則集（第一波）

| Alert Type | 觸發條件 | 嚴重度 | 原因 |
|-----------|---------|--------|------|
| `LONG_PENDING_ORDER` | pending 超過 14 天 | medium | 可直接用現有訂單資料計算 |
| `NEGATIVE_AVAILABLE` | `onHand - reserved < 0` | critical | 直接對應資料一致性問題 |
| `STOCKOUT_PROLONGED` | 低於安全庫存持續 ≥ 7 天 | critical | 對營運有直接風險 |

### 6.3 第二波擴充規則

- `DUPLICATE_ORDER`
- `ORDER_QUANTITY_SPIKE`
- `CUSTOMER_INACTIVE`
- `HIGH_VALUE_CUSTOMER_CHURN_RISK`
- `FREQUENT_CANCELLATION`
- `OVERDUE_PAYMENT`

### 6.4 架構

```
cron / scheduler
  -> AnomalyScanner
  -> anomalies table
  -> sync pull / dedicated endpoint
  -> NotificationCenter + Dashboard banner
```

### 6.5 資料表

```sql
CREATE TABLE anomalies (
  id           SERIAL PRIMARY KEY,
  alert_type   VARCHAR(64) NOT NULL,
  severity     VARCHAR(16) NOT NULL,
  entity_type  VARCHAR(32) NOT NULL,
  entity_id    INTEGER NOT NULL,
  message      TEXT NOT NULL,
  detail       JSONB,
  is_resolved  BOOLEAN DEFAULT FALSE,
  resolved_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);
```

### 6.6 UI 方針

- 通知中心可獨立頁面，但不強制先加底部 tab
- 儀表板只先顯示 critical / high 摘要
- 「標記已解決」必須回寫後端並同步至其他裝置

### 6.7 驗收標準

- 規則命中結果可人工重算
- resolved 狀態可跨裝置同步
- scanner 不可阻塞既有同步流程

---

## 7. P2-CRM：客戶健康度面板

### 7.1 落地策略

CRM 分兩段：

- **Stage 1**：RFM 只讀分級 + 客戶列表排序 / 篩選
- **Stage 2**：客戶詳情頁強化 + 互動記錄 + 異常掛載

### 7.2 RFM 評分

| 維度 | 說明 | 計算來源 |
|------|------|---------|
| R | 距最後訂單天數 | sales orders |
| F | 近 90 天訂單筆數 | sales orders |
| M | 近 90 天總金額 | sales orders |

### 7.3 分級

| 分數 | 分級 | 建議 |
|------|------|------|
| 12–15 | VIP | 定期維繫 |
| 9–11 | 活躍 | 持續跟進 |
| 6–8 | 觀察 | 主動關懷 |
| 3–5 | 流失風險 | 立即聯繫 |

### 7.4 Stage 1 範圍

| 功能 | 說明 |
|------|------|
| 客戶列表 RFM 標籤 | 先做列表可見化 |
| 排序 | 依 RFM / 最後下單日 / LTV |
| 篩選 | 僅顯示流失風險 |

### 7.5 Stage 2 範圍

| 功能 | 說明 |
|------|------|
| 客戶詳情頁健康度卡 | 顯示 R/F/M、LTV、週期 |
| 近期訂單摘要 | 顯示最近 5 筆 |
| 互動記錄 | 支援新增 / 刪除 / 同步 |
| 客戶異常 | 顯示與該客戶相關的 anomaly |
| 熱力圖 | 依 P2-VIS Wave 2 落地 |

### 7.6 新增資料表

```sql
CREATE TABLE customer_interactions (
  id           SERIAL PRIMARY KEY,
  customer_id  INTEGER NOT NULL REFERENCES customers(id),
  note         TEXT NOT NULL,
  created_by   INTEGER REFERENCES users(id),
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
```

### 7.7 風險

- 目前 repo 尚無獨立客戶詳情頁結構，需先補 UI flow
- 互動記錄一旦可離線新增，就必須納入 sync contract

---

## 8. P2-ACC：會計基礎

> 本階段仍不做複式記帳，只建立營運視角的 AR 與損益摘要。

### 8.1 為何最後做

1. 需要最多新欄位
2. 會碰既有出貨流程
3. 一旦欄位定義錯誤，後續修正成本高

### 8.2 階段拆分

- **Stage 1**：AR tracking
- **Stage 2**：Profit summary

### 8.3 Stage 1：AR

#### 新欄位

```sql
ALTER TABLE sales_orders ADD COLUMN payment_status VARCHAR(16) DEFAULT 'unpaid';
ALTER TABLE sales_orders ADD COLUMN paid_at TIMESTAMPTZ;
ALTER TABLE sales_orders ADD COLUMN due_date DATE;
ALTER TABLE customers ADD COLUMN payment_terms_days INTEGER DEFAULT 30;
```

#### AR 流程

```
shipped -> unpaid -> paid / written_off
```

#### UI

- 新增 Admin 專用 AR 頁
- 顯示未收金額、逾期金額、本月已收
- Aging buckets：0–30 / 31–60 / 61–90 / 90+

### 8.4 Stage 2：損益摘要

#### 新欄位

```sql
ALTER TABLE products ADD COLUMN cost_price NUMERIC(12,2);
```

#### 指標

| 項目 | 計算來源 |
|------|---------|
| 收入 | shipped orders |
| COGS | shipped item qty × cost_price |
| 毛利 | 收入 - COGS |
| 毛利率 | 毛利 / 收入 |

### 8.5 驗收標準

- due date 計算正確
- 標記已收款可多裝置同步
- 毛利數字可抽樣手算比對

---

## 9. 權限矩陣

| 功能 | Sales | Warehouse | Admin |
|------|-------|-----------|-------|
| 儀表板營收 / 訂單圖表 | ✅ | 🚫 | ✅ |
| 庫存趨勢圖表 | 🚫 | ✅ | ✅ |
| 通知中心查看 | 客戶/訂單類 | 庫存類 | 全部 |
| 通知中心解決 | 權限範圍內 | 權限範圍內 | 全部 |
| RFM / CRM | ✅ | 🚫 | ✅ |
| 互動記錄 | ✅ | 🚫 | ✅ |
| AR | 🚫 | 🚫 | ✅ |
| 損益摘要 | 🚫 | 🚫 | ✅ |

---

## 10. Migration 與契約策略

### 10.1 命名原則

舊版 `v4~v8` 命名取消，不直接沿用。

改用：

- backend: `P2-DB-01`, `P2-DB-02`, ...
- frontend Drift: 依實際 `schemaVersion` 往上遞增
- API contract: `sync v1.7` 或 `v1.6 addendum`

### 10.2 建議順序

| 順序 | 變更 |
|------|------|
| DB-01 | `anomalies` |
| DB-02 | `customer_interactions` |
| DB-03 | `sales_orders.payment_status / paid_at / due_date` |
| DB-04 | `products.cost_price` |
| DB-05 | `customers.payment_terms_days` |

> `rfm_score` 不建議先寫回 customers；優先做 server-side 計算或 materialized view，避免資料過時。

---

## 11. 新的推進順序與時程

### Sprint F（Foundation）— 1 週

| # | 任務 | 模組 |
|---|------|------|
| F1 | Phase 2 migration / contract 設計 | P2-FND |
| F2 | sync entityType 擴充 | P2-FND |
| F3 | analytics route skeleton + cache model | P2-FND |
| F4 | navigation / entry 設計 | P2-FND |
| F5 | 驗收基線與測試手冊 | P2-FND |

### Sprint A（VIS）— 1 至 1.5 週

| # | 任務 | 模組 |
|---|------|------|
| A1 | revenue / status-summary / top-sales API | P2-VIS |
| A2 | Dashboard 圖表整合 | P2-VIS |
| A3 | analytics cache + offline fallback | P2-VIS |

### Sprint B（ALT MVP）— 1 週

| # | 任務 | 模組 |
|---|------|------|
| B1 | anomalies table + scanner | P2-ALT |
| B2 | LONG_PENDING_ORDER / NEGATIVE_AVAILABLE / STOCKOUT_PROLONGED | P2-ALT |
| B3 | NotificationCenter + dashboard summary | P2-ALT |
| B4 | resolved sync flow | P2-ALT |

### Sprint C（CRM）— 1 至 1.5 週

| # | 任務 | 模組 |
|---|------|------|
| C1 | RFM API / server-side scoring | P2-CRM |
| C2 | 客戶列表標籤、排序、篩選 | P2-CRM |
| C3 | customer_interactions + sync | P2-CRM |
| C4 | 客戶詳情頁強化 | P2-CRM |
| C5 | 熱力圖（若 Sprint A Wave 2 ready） | P2-CRM |

### Sprint D（ACC）— 1 至 1.5 週

| # | 任務 | 模組 |
|---|------|------|
| D1 | payment_terms / payment_status / due_date | P2-ACC |
| D2 | AR 頁 + aging buckets | P2-ACC |
| D3 | overdue anomaly | P2-ACC + P2-ALT |
| D4 | cost_price + 毛利摘要 | P2-ACC |

### 總工期

- 原始估算：3.5 週
- 修正版估算：**4.5–6 週**

---

## 12. 技術決策

| 決策 | 選項 | 理由 |
|------|------|------|
| 圖表套件 | `fl_chart` | Flutter 生態成熟 |
| 聚合計算位置 | PostgreSQL / backend | 避免前端運算過重 |
| 異常偵測觸發 | scheduler / cron | 不依賴前端在線 |
| RFM 計算位置 | server-side | 保持多裝置一致 |
| AR anomaly | 納入 anomaly engine | 不另造通知機制 |
| 複式記帳 | 不納入本 Phase | 先驗證 AR 與損益需求 |

---

## 13. 驗收標準

| 模組 | 驗收條件 |
|------|---------|
| P2-FND | migration 成功、sync contract 可跑通、新導航不破壞既有流程 |
| P2-VIS | 圖表數值正確，離線可看快取，refresh 正常 |
| P2-ALT | 規則命中正確、resolved 可同步、badge 計數準確 |
| P2-CRM | RFM 可手算比對、互動記錄離線新增可同步、詳情頁資料正確 |
| P2-ACC | AR aging 正確、付款狀態同步正常、毛利可抽樣核對 |

---

## 14. 最終優先順序

1. `P2-FND`
2. `P2-VIS`
3. `P2-ALT`
4. `P2-CRM`
5. `P2-ACC`

這個排序的原則是：

- 先保護同步與資料穩定性
- 再交付高可見度功能
- 最後處理牽動欄位最多的會計能力

---

*文件維護者：Codex | 本版目的：將 Phase 2 從理想規劃重寫為可執行版本*
