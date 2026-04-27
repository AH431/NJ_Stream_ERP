# Changelog — NJ Stream ERP

所有已完成的 Sprint 記錄。格式：`## [Sprint N] 日期範圍`

---

## [Phase 2 Sprint C] 2026-04-26（customer interactions）

### 新增
- 客戶詳情頁（CustomerDetailScreen）— 互動時間軸（visit / call / email）
- InteractionDao — 本地互動記錄 CRUD + 離線佇列支援
- 客戶列表頁點入詳情路由

**Commit**：`6401672` phase2: customer interactions

---

## [Phase 2 Sprint A + B] 2026-04-25（VIS + ALT）

### 新增（Sprint A — VIS 分析）
- AnalyticsProvider — 後端 `/api/v1/analytics/*` 資料拉取，15 分鐘本機快取
- 月營收趨勢（RevenuePoint）、訂單狀態分佈（OrderStatusCount）、Top 產品排行
- RfmProvider — RFM 客戶分群（Recency / Frequency / Monetary）
- AnomalyProvider — AnomalyScanner 掃描結果拉取 + 標記已解決
- Dashboard 整合 Analytics 入口
- 後端 `analytics.route.ts` + `anomaly_scanner.service.ts`

### 新增（Sprint B — ALT 推播）
- Firebase Cloud Messaging 整合（`fcm_service.dart`、`fcm.service.ts`）
- DeviceTokensSchema（後端）— 裝置 token 註冊 / 更新
- NotificationScreen — 異常清單、嚴重度篩選、標記已解決
- `notifications.route.ts` — push 觸發端點

### 新增（P2-ACC 應收帳款）
- ArScreen（Admin 專用）— aging 分桶總覽 + 未收訂單明細
- ArProvider — 應收帳款拉取 + 標記已付款 / 呆帳沖銷
- `ar.route.ts` — 後端 AR 查詢與更新端點

**Commit**：`aee8a4f` feat(phase2): implement Sprint A (VIS) and Sprint B (ALT) modules

---

## [Sprint 5] 2026-04-20 ~ 2026-04-21

### 新增
- 雙語 UI 完整切換（14 個 feature screens 全數遷移至 AppStrings）
- AppStrings 語言持久化（FlutterSecureStorage，Activity recreation 後設定保留）
- scrcpy 錄影工作流程文件

### 修復
- CSV Import FileProvider 根因修復（改用 dart:io 資料夾掃描，移除 FilePicker 依賴）
- product_form / customer_form 儲存失敗訊息雙語化
- 補齊 AppStrings 缺漏鍵值（custTaxId、btnSavingProduct、quotErrProduct、quotErrPriceEmpty）

### 文檔
- Sprint Retrospective（S1–S5 Scrum 回顧）
- 專案執行效率分析（里程碑對比表）
- 下個專案執行 Playbook（Lessons Learned）
- 文檔結構優化建議

**Commit**：`5ff7aa6` feat: migrate all 14 feature screens to AppStrings bilingual system

---

## [Sprint 4] 2026-04-15 ~ 2026-04-18

### 新增
- Issue #34：離線 ID chain FK remap（localId → serverId 兩段式映射）
- Issue #35：canReserve 防重複預留（reservedAt 欄位 + 鎖定機制）
- Issue #36：Dev Settings — API Base URL 執行期設定
- Issue #17：Admin Cleanup endpoint（processed_ops + 軟刪除清理）
- Issue #16：CSV 批次匯入（Product / Customer / Inventory 三種類型）
- Dashboard KPI 卡片（待出貨訂單、低庫存警示、本月報價總額）
- PDF 文件產生（報價單 / 銷售訂單 / 月結對帳單，含 NotoSansTC 中文字型）
- Email 整合（Ethereal dev / Gmail prod，send quotation/order/statement）
- CI/CD Pipeline（GitHub Actions：npm ci + dart analyze + npm audit；Dependabot）
- 資安強化（rate limiting 50req/min + login 10req/min、bcrypt rounds 12、R8 obfuscation、firewall 127.0.0.1）
- Cloudflare Quick Tunnel 設定

### 修復
- Bug #1：warehouse role 缺少 `sales_order:update` 權限
- Bug #2：離線 ID 跨表引用斷鏈（FK remap，Issue #34）
- Bug #3：stale reservedAt 在 INSUFFICIENT_STOCK 409 後未清除

**Commit**：`b180db5` feat: bilingual UI, CSV import redesign, language persistence

---

## [Sprint 3] 2026-04-13 ~ 2026-04-14

### 新增
- Issue #9：DELTA_UPDATE 四種 type（reserve / cancel / in / out）
- Issue #10：庫存快照列表 UI（低庫存 badge、三欄數字）
- Issue #11：StockIn Dialog + Race Condition 測試
- Issue #12：ReserveInventoryDialog（預留確認、等待 / 拆單選項）
- Issue #13：ShipOrderDialog（出貨預覽 + 庫存扣減預覽）
- Issue #14：Walking Test Phase 0–5（Android 建置、Sony XA1 實機驗證）
- Issue #7：報價 API + 報價轉訂單（First-to-Sync wins）
- Issue #8：報價單 UI（稅額切換 + Decimal）

### 驗收
- curl 驗證（reserve / cancel / in / out）：4/4 ✅
- Walking Test Phase 0–5：全通過 ✅

---

## [Sprint 2] 2026-04-12 ~ 2026-04-13

### 新增
- Issue #5：Customer / Product 列表 UI + 離線新增 + 軟刪除
- Issue #6：LWW 衝突解決實作（updated_at 比較）
- Flutter 專案初始化（Drift 10 張表、build_runner）
- SyncProvider Pull/Push 骨架 + 離線佇列

---

## [Sprint 1] 2026-04-10 ~ 2026-04-12

### 新增
- Issue #1：API Contract Sync v1.6（OpenAPI，Contract-First 單一真相來源）
- Issue #2：Fastify + Drizzle ORM + PostgreSQL（8 張資料表、Docker）
- Issue #21：Auth Contract（api-contract-auth.yaml）
- Auth JWT 中間件 + bcrypt + Role 權限矩陣
- POST /api/v1/sync/push 骨架 + 錯誤碼


### W1 Gate
- API contract 凍結 ✅
- Docker + Drizzle Studio 連線 ✅
- flutter doctor -v 全綠 ✅