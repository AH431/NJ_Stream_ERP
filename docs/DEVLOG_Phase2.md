# NJ Stream ERP — Phase 2 開發日誌

> **執行計畫**：NJ_Stream_ERP Phase2 PRD V2_codex.md  
> **設計規格**：NJ_Stream_ERP Phase2 PRD v1.0.md  
> **負責工程師**：AH431  
> **記錄格式**：`[YYYY-MM-DD] Sprint / 票號 — 說明`

---

## 2026-04-18 — Sprint F（Foundation）+ Git Security

### 安全性 / .gitignore 補強
- 新增 `.gitignore` 規則，排除具資安疑慮的文件類型與路徑：
  - `*.pdf`, `*.docx`, `*.xlsx`, `*.pptx`（合約、報價單、財務試算表）
  - `docs/api-contract-*.yaml`（API 契約，含 endpoint 結構細節）
  - `docs/nj_stream_erp_erd.html`（資料庫 ERD，含完整 schema 細節）
- 已追蹤的敏感檔案以 `git rm --cached` 移除追蹤，本地副本保留。

---

## 2026-04-18 — Sprint A（P2-VIS 可視化分析）

### P2-VIS-01 後端：Analytics REST API
**新增** `packages/backend/src/routes/analytics.route.ts`

| 端點 | 權限 | 說明 |
|---|---|---|
| `GET /api/v1/analytics/revenue?months=N` | admin, sales | 月營收折線圖資料（最近 N 個月，預設 6） |
| `GET /api/v1/analytics/orders/status-summary` | admin, sales | 訂單狀態分佈（圓餅圖） |
| `GET /api/v1/analytics/products/top-sales?days=N&limit=N` | admin, warehouse | 熱銷商品排行（依銷售數量） |

- 使用 Drizzle `sql` tag 撰寫原生 SQL 聚合查詢（非 ORM query builder）
- 修正 `requireRole` 呼叫方式：由陣列傳參改為 spread 傳參（`app.requireRole(ADMIN, SALES)`）

### P2-VIS-02 前端：AnalyticsProvider
**新增** `packages/frontend/lib/providers/analytics_provider.dart`

- `ChangeNotifierProxyProvider<SyncProvider, AnalyticsProvider>`，複用 `SyncProvider.authenticatedDio`
- 15 分鐘記憶體快取（`_CacheEntry<T>`），`force: true` 可強制刷新
- `fetchAll()` 以 `Future.wait` 並行拉取三支 API
- 資料模型：`RevenuePoint`、`OrderStatusCount`、`TopProduct`

**修改** `packages/frontend/lib/providers/sync_provider.dart`
- 新增 `Dio get authenticatedDio => _dio;` getter 供 AnalyticsProvider / AnomalyProvider 複用

### P2-VIS-03 前端：Dashboard 圖表
**重寫** `packages/frontend/lib/features/dashboard/dashboard_screen.dart`

- 轉為 `StatefulWidget`，`initState` 觸發 `AnalyticsProvider.fetchAll()`
- 新增圖表元件（`fl_chart: ^0.69.0`）：
  - `_RevenueLineChart`：6 個月月營收折線圖，長壓顯示 tooltip
  - `_OrderStatusDonut`：訂單狀態圓餅圖，中心顯示總筆數 + 圖例
  - `_TopProductsBar`：熱銷商品水平條形圖（`LinearProgressIndicator`，不依賴 fl_chart）
  - `_LastUpdatedLabel`：顯示快取時間戳
- 原有卡片元件（`_ConfirmedOrderCard`、`_MonthlyQuotationCard`、`_LowStockSection` 等）全數保留，無破壞性變更
- 修正 `use_build_context_synchronously`：在 `await` 前捕捉 `AnalyticsProvider` 參考

**修改** `packages/frontend/pubspec.yaml`
- 新增 `fl_chart: ^0.69.0`（MIT 授權）

---

## 2026-04-24 — Sprint B（P2-ALT 異常偵測通知）

### P2-DB-01 後端：anomalies 資料表 Schema
**新增** `packages/backend/src/schemas/anomalies.schema.ts`

```
anomalies: id, alertType, severity, entityType, entityId,
           message, detail(jsonb), isResolved, resolvedAt, createdAt, updatedAt
```

- 索引：`idx_anomalies_unresolved (isResolved, severity)`、`idx_anomalies_entity (entityType, entityId)`
- **修改** `packages/backend/src/schemas/index.ts`：新增 re-export

> ⚠️ **部署注意**：需在目標 DB 執行 `npm run db:generate && npm run db:migrate` 以建立 anomalies 資料表。

### P2-ALT-01 後端：AnomalyScanner 排程服務
**新增** `packages/backend/src/services/anomaly_scanner.service.ts`

| 規則 | 嚴重度 | 條件 |
|---|---|---|
| `LONG_PENDING_ORDER` | medium | pending 訂單建立超過 14 天 |
| `NEGATIVE_AVAILABLE` | critical | onHand − reserved < 0（資料異常） |
| `STOCKOUT_PROLONGED` | critical | available < minStockLevel（且 minStockLevel > 0） |

- 去重邏輯：`NOT IN (SELECT entity_id FROM anomalies WHERE alert_type=X AND is_resolved=FALSE)`
- 自動解除：`autoResolveStale()` 在每輪掃描後執行，條件消失即標記 `is_resolved=TRUE`
- 型別轉換：`db.execute()` 結果透過 `as unknown as Array<{...}>` 雙步轉型（Drizzle RowList 型別限制）

### P2-ALT-02 後端：Anomalies REST API
**新增** `packages/backend/src/routes/anomalies.route.ts`

| 端點 | 說明 |
|---|---|
| `GET /api/v1/anomalies` | 未解決異常清單（依嚴重度→時間排序），`?resolved=true` 查已解決 |
| `PATCH /api/v1/anomalies/:id/resolve` | 標記已解決，已解決狀態回傳 404 |

**修改** `packages/backend/src/app.ts`
- 註冊 `anomaliesRoutes`（prefix: `/api/v1/anomalies`）
- `onReady` hook：10 秒延遲後首次執行掃描，之後每小時循環

### P2-ALT-03 前端：AnomalyProvider
**新增** `packages/frontend/lib/providers/anomaly_provider.dart`

- `ChangeNotifierProxyProvider<SyncProvider, AnomalyProvider>`
- 5 分鐘記憶體快取（比 Analytics 更短，即時性需求更高）
- `resolve(id)` 樂觀更新：立即從本地清單移除，不等下次 fetch
- `urgentCount`：critical + high 未解決筆數（AppBar badge 用）

### P2-ALT-04 前端：NotificationScreen
**新增** `packages/frontend/lib/features/notifications/notification_screen.dart`

- `initState` 強制刷新（`force: true`）
- `_FilterBar`：FilterChip 列，all / critical / high / medium + 各類別計數
- `_AnomalyCard`：嚴重度圖示 + alertType 標籤 + 說明文字 + 實體參照 + 解決按鈕
- Chinese alert type labels：`LONG_PENDING_ORDER`→訂單停滯、`NEGATIVE_AVAILABLE`→庫存異常、`STOCKOUT_PROLONGED`→長期缺貨
- 修正 `use_build_context_synchronously`：在 `await` 前捕捉 `ScaffoldMessenger` 參考

### P2-ALT-05 前端：AppBar 通知鈴鐺整合
**修改** `packages/frontend/lib/main.dart`

- `MultiProvider` 新增 `ChangeNotifierProxyProvider<SyncProvider, AnomalyProvider>`
- `_HomeScreenState.initState`：登入後觸發 `AnomalyProvider.fetchAnomalies()`（背景，不阻塞 UI）
- AppBar actions 新增 `_AnomalyBell`，點擊 push route 至 `NotificationScreen`
- **新增** `_AnomalyBell` widget：`urgentCount > 0` 時顯示紅色 Badge

### 其他修正（非功能性）
- **移動** `lib/scratch/check_order_38.dart` → `scratch/`（開發用腳本誤放 lib/ 導致分析錯誤）
- **修正** `packages/backend/src/services/pdf.service.ts`：補上缺失的 `LineItem` 型別定義（預存 bug）

---

## 驗證結果（2026-04-24）

```
flutter analyze lib/
  → 1 issue (pre-existing unused_local_variable in customer_form_screen.dart)
  → Sprint A / B 相關檔案：0 errors, 0 warnings

npm run build (backend)
  → tsc + tsc-alias 編譯成功，0 errors
```

---

## 待辦（明日裝置測試前）

- [ ] 執行 `npm run db:generate && npm run db:migrate`（建立 anomalies 表）
- [ ] 手機實測 Sprint A：Dashboard 圖表載入、下拉刷新、語言切換
- [ ] 手機實測 Sprint B：鈴鐺 badge 顯示、NotificationScreen 篩選、標記解決
- [ ] 確認 Cloudflare Tunnel URL 並更新手機 App 的 API 端點設定

---

## 下一階段

| Sprint | 模組 | 主要功能 |
|---|---|---|
| Sprint C | P2-CRM | 客戶分級（RFM 評分）、跟進記錄、聯絡人管理 |
| Sprint D | P2-ACC | 應收帳款追蹤、付款記錄、逾期提醒 |
