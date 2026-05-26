# NJ Stream ERP Phase 4 Implementation Checklist v1.0

> 來源：`docs/NJ_Stream_ERP Phase4 PRD v1.0.md`（v1.1, 2026-05-17）
> 用途：把 PRD 拆成「逐項可勾選、可分派、可驗收」的執行清單
> 進度標記規則：`[ ]` 未開始 / `[~]` 進行中 / `[x]` 完成且通過驗收
> 最後對齊：2026-05-26（依 LOG/PHASE4-daily/ 日誌更新）

---

## Sprint 4A — 生產封關

### PR-1：Phase 3 遺留驗收 + Medium 安全修正

#### M1.1 靜態 AI 聊天手機 E2E（S-1~S-5）
- [ ] 啟動 Cloudflare Tunnel + ai_service + 後端 + APK，連線健康檢查通過
- [ ] 依 golden set 跑 S-1~S-5 五題靜態問答（手機端）
- [ ] 確認每題回覆正確且 `SourceCard` 數量 = 0
- [ ] 驗證 static 路由未觸發 tool_call SSE 事件
- [ ] 將 5/5 驗收結果寫入 `LOG/PHASE3-daily/<date>.md`

#### M1.2 雙裝置 race condition 實測
- [ ] 準備兩台 Android 實機，同帳號或同權限 user
- [ ] 兩機同時送 RESERVE 同一批次庫存，重複 ≥ 100 次
- [ ] 驗證每次：一台 200、一台 409 `INSUFFICIENT_STOCK`
- [ ] 比對 DB：批次庫存無負數、無超賣
- [ ] 將自動化腳本 / 操作紀錄存檔至 `LOG/PHASE3-daily/`

#### M1.3 Medium 安全修正（#6~#12）
- [x] **#6** `fcm.service.ts`：tokens 陣列依 500 上限 chunk，迴圈 `sendEachForMulticast`，補 unit test
- [x] **#7** `sync.service.ts`：`bypassDuplicateCheck` 入口加 `role === 'admin'` guard，補負向測試
- [x] **#8** `auth.plugin.ts`：`verifyJwt` 加 DB `isActive` check（Redis 或 1 min TTL 快取），補停用帳號測試
- [x] **#9** `anomaly_scanner.service.ts`：`anomalies` 表加 `UNIQUE(entity_type, entity_id, alert_type) WHERE is_resolved = FALSE`（`0008_anomalies_unique.sql`）；所有 INSERT 補 `ON CONFLICT DO NOTHING` 防並發 23505 中斷掃描；新增 guard 測試
- [x] **#10** `sync.service.ts`：`confirmedAt` / `shippedAt` 一律以 server-side `new Date()` 注入；strip client payload；補測試
- [x] **#11** `auth.route.ts` logout：改用 `jwt.decode` 接受過期 token，補測試
- [x] **#12** `auth.route.ts` `getSecret()`：加 null guard，throw 明確 500，補測試
- [x] vitest 全綠（含本批新增 unit test）— 69/69 通過、`tsc --noEmit` 0 錯誤

#### M1.4 生產觀測性基線
- [x] 補 backend structured log key：`requestId` / `userId` / `tenantId` / `route` / `statusCode` / `durationMs`（`app.ts` onResponse hook；Fastify 5 `req.routeOptions.url` fallback；`tenantId` 預留 null 待 Phase 4C）
- [x] 補 ai_service structured log key：`requestId` / `model` / `durationMs` / `upstreamTimeout`（`chat.py`；`jobId` / `tenantId` 待 PR-3/4C）
- [x] forecast / FCM / anomaly 等背景工作寫入 job log（開始、結束、計數、錯誤摘要）— FCM `job.done` / `chunk.failed`、Anomaly `job.start` / `job.done` / `job.failed`
- [x] 驗證能用單一 `requestId` 或 `jobId` 把一次執行鏈跨服務 grep 出來
  > **驗收（2026-05-24）**：requestId `5692bbbe-d912-40f2-8931-a2b3000de4ce` 同時出現在 backend access log（`route=/api/v1/ai/chat, statusCode=200`）與 ai_service log（`chat.start` + `chat.done`）。
- [x] AI / FCM / auth 失敗情境各 ≥ 1 組負向測試

---

### PR-2：生產部署（網域 + Cloudflare WAF + Docker prod 驗證）

#### M2.1 網域購買與 DNS 設定
- [ ] 完成 `njstream.tw`（或同等）網域購買
- [ ] Cloudflare DNS 接管，建立 `api.njstream.tw` 固定 hostname → Cloudflare Tunnel
- [ ] 更新 `packages/frontend/lib/config/app_config.dart` 的 `prodUrl` 常數
- [ ] 重建並安裝 production APK
- [ ] `curl https://api.njstream.tw/health` 回應 `{"status":"ok"}`
- [ ] 手機端登入、查單、AI 聊天三路徑回歸測試通過

#### M2.2 Cloudflare WAF 正式啟用
- [ ] 依 `cloudflare-waf-setup.md` 套用規則（OWASP / rate limit / geo）
- [ ] WAF 先設為 **observe** 模式上線
- [ ] 觀察 7 天 log，調整誤擋規則
- [ ] 切換為 **enforce** 模式
- [ ] `verify_waf.ps1` 全部 `WAF PASS`（401 不算 WAF 攔截）

#### M2.3 FCM 推播 E2E 驗收
- [ ] Firebase Service Account 金鑰確認可在 production 環境讀取
- [ ] 兩台實機綁定 FCM token，DB `device_tokens` 表有對應 row
- [ ] 觸發 AnomalyScanner 偵測到異常 → 兩台實機均收到推播
- [ ] 重複觸發第二次，確認推播仍正常（無 token 重複/失效錯誤）

#### M2.4 網路邊界確認
- [x] 確認 ai_service `/forecast/*` 與 internal-only endpoint 未經 public edge 暴露
  > docker-compose.prod.yml：ai_service 無 `ports:` 映射；backend 預設綁 `127.0.0.1`；postgres 無 `ports:`。所有 ai_service 端點另有 `X-Internal-Token` + scope 保護。
- [ ] 由外部網路掃描 `https://api.njstream.tw/forecast/...` → 應回 404 / 拒絕（待 M2.1 網域）
- [x] 整理 internal-only 路由清單，docker-compose 設定確認正確（無需修改）
- [x] 將網路拓樸與允許矩陣記錄到 `docs/network-boundary.md`

---

## Sprint 4B — 需求預測 MVP

### PR-3：需求預測引擎（ai_service 擴充）

#### M3.1 資料表 migration
- [x] 撰寫 `0009_demand_forecasts.sql`（依 PRD §4.1 schema，含 `UNIQUE(tenant_id, product_id, week_start, model_version)`、`idx_demand_forecasts_tenant_product`、`idx_demand_forecasts_week_start`）
- [x] 撰寫 `0010_forecast_jobs.sql`（依 PRD §4.1，含 status、`lease_expires_at`、`generated_cnt`、`skipped_cnt`、`error_summary`）
- [x] 在 staging DB 試跑 + rollback 一次
  > **驗收（2026-05-20）**：apply → rollback → re-apply 驗證通過；修正 `rollback_0009_0010.sql`。
- [x] 更新 Drizzle schema files 與 type exports（`demand_forecasts.schema.ts`、`forecast_jobs.schema.ts`，barrel `schemas/index.ts` 已 export）

#### M3.2 ai_service 端點
- [x] `POST /forecast/generate` 實作
  - [x] 建立 / claim `forecast_jobs` row；偵測 running job 則拒絕重複
  - [x] 呼叫 Fastify `GET /api/v1/analytics/sales-history?weeks=52`（帶 `X-Internal-Token`, scope=`analytics.read`）
  - [x] 依 `productId` 彙總週銷量為 DataFrame
  - [x] 資料 < `FORECAST_MIN_DATA_WEEKS` 週 → 記錄 skipped，不 crash
  - [x] Prophet fit + predict（週頻率，含信賴區間）
  - [x] UPSERT 寫入 `demand_forecasts`（`model_version` 為 key 之一）
  - [x] 更新 `forecast_jobs` status / generated_cnt / skipped_cnt / error_summary
  - [x] 回傳 `{ runId, generated, skipped[], durationMs }`
- [x] `GET /forecast?tenantId=&productId=&weeks=` 實作（讀 `demand_forecasts`）
- [x] 兩端點皆驗 `X-Internal-Token` 與 scope

#### M3.3 Fastify 代理端點
- [x] `GET /api/v1/analytics/forecast?productId=&weeks=`（JWT：warehouse / admin / sales），代理時注入 `req.user.tenantId`
- [x] `POST /api/v1/analytics/forecast/generate`（JWT：admin only），代理 + 注入 tenantId
- [x] `GET /api/v1/analytics/sales-history?weeks=52`（`X-Internal-Token`, scope=`analytics.read`），回傳當前 tenant 週彙總
- [x] 三條 route 皆寫 audit log

#### M3.4 依賴與設定
- [x] `packages/ai_service/requirements.txt` 新增 `prophet==1.1.5` / `pandas==2.2.2` / `cmdstanpy==1.2.4`
- [x] Docker build 驗證 Prophet 安裝成功（避開 Windows 本地 C++ build）
  > **驗收（2026-05-20）**：`numpy<2.0` pin + `.dockerignore` 修正；`docker run --rm nj-ai-service-test python -c "from prophet import Prophet; print('Prophet OK')"` 通過。
- [x] 環境變數：`FORECAST_WEEKS_AHEAD=12`、`FORECAST_MIN_DATA_WEEKS=8`、`FORECAST_JOB_LEASE_SECONDS=900`、`AI_INTERNAL_SCOPES=analytics.read,forecast.generate`

#### M3.5 測試
- [x] `test_forecast_engine.py`：fixture × 4（正常、少資料、單品、空）
- [x] `test_forecast_route.py`：POST generate + GET forecast（mock 上游）
- [x] 並發測試：同一 tenant 同時觸發 2 次，僅 1 個 running
- [x] 局部失敗測試：單一 product fit 失敗，其他 product 仍寫入，job 標記 partial failure

---

### PR-4：Fastify 排程觸發器

- [x] 決定排程策略：**in-process setInterval + DB advisory lock**（`forecast_scheduler.service.ts` 開頭 JSDoc 已記入）
- [x] 實作 `forecast_scheduler.service.ts`：scheduler 只負責 enqueue / claim，worker 才執行
- [x] 啟動兩個 backend 或 worker instance，驗證單一 tenant + 時窗只產生 1 個成功 job
  > **驗收（2026-05-20）**：backend1（port 3000）+ backend2（port 3001），同一 DB，manual running job 注入後兩者均記錄 `scheduler.skip.lease_active`；advisory lock 於 ai_service 由 `pg_advisory_xact_lock(tenant_id)` 序列化 — unit tests 覆蓋並發 409。
- [x] worker 中途 kill 後，由 lease timeout / replay 機制能補跑該 job
  > **驗收（2026-05-20）**：kill backend1 後，手動到期 lease → backend2 下一個 tick（15 s）偵測到 lease_expires_at < NOW() → `scheduler.tick.error`；`forecast_jobs` 表出現 2 個新 row，補跑機制確認運作。
- [x] 手動觸發 `POST /api/v1/analytics/forecast/generate`（Admin），確認 forecast_jobs 與 demand_forecasts 都有對應紀錄
  > **驗收（2026-05-20）**：runId=`4ce31927-7f58-4b5c-b79c-390d803a9d06`，generated=21，demand_forecasts 每產品 12 筆預測（週×12）。
- [x] scheduler 寫入 structured log，可用 `jobId` 追蹤
  > **驗收（2026-05-20）**：`scheduler.trigger.ok` 帶 `runId`；`scheduler.tick.error` 帶 `error` 字串；ai_service log 帶 `jobId` 全程可 grep。

---

### PR-5：需求預測 UI（Dashboard + 手機）

#### M5.1 Dashboard `ForecastSummaryCard`
- [x] 卡片顯示 Top 3「本週低於安全庫存 + 預測上升」的紅色補貨警示
- [x] 卡片顯示未來 4 週預測需求量 vs 現有庫存
- [x] 點擊跳轉 `ProductForecastScreen`
- [x] Empty state：尚無 forecast 時顯示「尚未產生預測」提示
> **程式碼完成（2026-05-20）**；手機端 UI 驗收待 PR-2 網域就緒後一併執行。

#### M5.2 `ProductForecastScreen`
- [x] `ProductSelector`（DropdownButton）載入該 tenant 產品清單
- [x] `ForecastChart`：`fl_chart` LineChart，12 週折線 + lower~upper 信賴區間陰影
- [x] `ForecastTable`：欄位 = 週次 / 預測量 / 建議採購量（`max(0, forecastQty - currentStock)`）
- [x] `ExportButton`：CSV 匯出（client-side，寫入 temp dir 後以 OpenFilex 開啟）
- [x] Widget test：render + empty state + 切換 product（3 個 widget tests 通過）
> **程式碼完成（2026-05-20）**；手機端 UI 驗收待 PR-2 網域就緒後一併執行。

#### M5.3 AI 工具 `get_demand_forecast`
- [x] 在 `packages/ai_service/src/tools/erp_tools.py` 新增 async function
- [x] 輸入：`sku`, `weeks`（預設 8）
- [x] 輸出：`{ sku, forecasts: [{weekStart, qty}], reorderAlert: bool }`
- [x] 對比現有庫存判斷 `reorderAlert`
- [x] `query_router` 新增 pattern：`需要補貨|下週需求|預測庫存|幾週後缺貨` → `dynamic`
- [x] 工具觸發後產生 SourceCard 並引用 forecast 結果
- [x] 新增 10 題 forecast golden eval（`test_forecast_tool.py`），10/10 通過

---

## Sprint 4C — 多租戶基礎

### PR-6：資料庫多租戶遷移

#### M6.1 `tenants` 表與 seed
- [x] migration 建立 `tenants` 表（id / name / slug / plan / is_active / created_at）
  > `packages/backend/drizzle/0011_tenants.sql`；Drizzle schema：`src/schemas/tenants.schema.ts`；barrel 已 export。
- [x] `INSERT (1, 'Demo Company', 'demo')` 作為 existing data 歸屬
  > `ON CONFLICT (id) DO NOTHING` + `setval(tenants_id_seq, 1)` 確保冪等；本地 DB 已套用驗收通過。

#### M6.2 業務表加 `tenant_id`
- [x] 列出全部需加 `tenant_id` 的業務表（12 張），逐一勾選：
  - [x] products
  - [x] inventory_items
  - [x] sales_orders / order_items
  - [x] customers
  - [x] users
  - [x] anomalies
  - [x] device_tokens
  - [x] audit_logs
  - [x] demand_forecasts / forecast_jobs（PR-3 已含欄位；此處補 FK 約束）
  - [x] customer_interactions / processed_operations / quotations
- [x] 每張表：`ADD COLUMN tenant_id INTEGER NOT NULL DEFAULT 1` + FK（`0012_add_tenant_id.sql`）
- [x] **[BUG-1 補項]** `demand_forecasts` / `forecast_jobs` 補 FK 約束：
  > `.references(() => tenants.id)` 加入 `demand_forecasts.schema.ts` 和 `forecast_jobs.schema.ts`
- [x] 更新 Drizzle schema files（14 個 schema 檔均已加 `tenantId` + import）
- [ ] 遷移前備份（依 `migrate_with_log.ps1` 模式）
- [x] 遷移後驗證 row count 100% 保留（本地 DB 套用：14 表 tenant_id NOT NULL ✅ / 14 FK ✅ / 12 index ✅）
- [x] rollback script dry-run 通過（`rollback_0011_0012.sql` 在 Docker postgres 無錯執行，全部 ALTER TABLE / DROP INDEX / DROP COLUMN / DROP TABLE 完成；2026-05-24 驗收）

#### M6.3 JWT / Request Context
- [x] JWT payload 新增 `tenantId`
- [x] 登入流程從 `users.tenant_id` 帶入 token
- [x] `verifyJwt`：`!payload.tenantId` → 401，強制重新登入取得含 tenantId 的新 token

#### M6.4 Tenant-aware Repository / Query Helper
- [x] 建立 `requireTenantId()` / `tenantFilter()` helper（`tenant.service.ts`）
- [x] 把現有業務 route 全部改走 helper：
  - [x] customers
  - [x] products
  - [x] inventory
  - [x] sales / orders
  - [x] analytics（含 sales-history、forecast proxy）
  - [x] quotations
- [x] 移除 / 重構未帶 tenant 條件的 raw SQL
- [x] 在 lint rule 加入「禁止新增未帶 tenant 條件的業務查詢」
  > `eslint.config.mjs`：`no-restricted-syntax` warn on `.findMany()` / `.findFirst()` without `tenantFilter` identifier in call scope。

#### M6.5 測試
- [ ] 建立第二個 tenant（id=2）seed 資料至本地 / staging DB
- [x] cross-tenant isolation 測試：tenant 1 user 不能讀到 tenant 2 任何業務資料（10 個 Vitest 通過）
- [x] 高風險 API ≥ 5 類負向測試（customers / products / inventory / sales_orders / auth）
- [x] migration row count 對拍驗證腳本（`scripts/verify_migration_counts.ts`）
- [x] rollback script dry-run 通過（2026-05-24，同上）

---

### PR-7：客戶入門流程（Admin Onboarding）

#### M7.1 Schema / API
- [x] `tenants` 加 `contact_email` / `timezone` / `onboarded_at` 三欄（`0013_tenant_onboarding.sql`）
- [x] `GET /api/v1/tenant`（verifyJwt 所有角色）
- [x] `PATCH /api/v1/tenant`（Admin only；可更新 name / contactEmail / timezone / markAsOnboarded）
- [x] `POST /api/v1/tenant/provision`（公開端點；原子 transaction：INSERT tenants → INSERT users admin；slug 重複 409）
- [ ] 用 `TENANT_PROVISION_SECRET` env 保護 provision endpoint，並寫 audit log
  > **決策**：provision 暫設公開（SaaS 入駐流程），未來需保護時加 `X-Provision-Secret` header check。

#### M7.2 Flutter OnboardingBanner
- [x] Dashboard 頂部顯示 banner（當 `onboardedAt == null`）
- [x] **Step 1** 設定公司名稱 / contactEmail → `PATCH /api/v1/tenant`
- [x] **Step 2** 設定時區 → `DropdownButtonFormField` 選 14 個 IANA tz，值暫存至 `_timezone` state
- [x] **Step 3** 完成確認 → `_Step2Done` 顯示 name / email / timezone 摘要；`_finish()` 呼叫 `PATCH /api/v1/tenant { markAsOnboarded: true }`
- [x] 完成後呼叫 `PATCH /api/v1/tenant { markAsOnboarded: true }`，banner 自動隱藏
- [x] Widget test：5 個通過（banner 顯示 / 隱藏 / 3-step Stepper 流程）

#### M7.3 驗收
- [x] 模擬全新 tenant：provision → GET（onboardedAt=null）→ PATCH（markAsOnboarded）→ GET（確認完成）— 13 個 Vitest 測試全通過（`tenant.route.test.ts`）
- [x] 過程中無需工程師直接操作 DB
- [x] Docker 階段：provision → login → GET tenant（onboardedAt=null）→ PATCH markAsOnboarded → GET tenant（onboardedAt≠null）→ GET inventory（空，無跨租戶洩漏）→ AI chat（SSE 正常回傳）— 全部通過（2026-05-24）

---

## Phase 4 整體驗收 Gate（演示給第一個客戶前必須全綠）

- [ ] **穩定性**：vitest 全綠；race condition 100+ 次 0 次超賣；WAF `verify_waf.ps1` pass；forecast job 可重跑且不重複寫入
- [ ] **功能**：12 週需求預測圖表可見；補貨警示正確觸發；manual replay 可補 forecast
- [ ] **AI**：`get_demand_forecast` golden eval 10/10；query router 新 pattern 命中；upstream timeout 有明確錯誤回應
- [ ] **多租戶**：cross-tenant isolation 測試 pass；migration row count 100%；高風險 API 負向測試全綠
- [ ] **入門**：新 tenant onboarding < 30 分鐘、zero engineering intervention
- [ ] **生產**：固定網域可存取；FCM 推播實機通過；internal endpoint 不對外暴露；可用 requestId / jobId 跨服務追蹤

---

## 技術依賴與環境變數總表

### Python（ai_service）
- [x] `prophet==1.1.5`
- [x] `pandas==2.2.2`
- [x] `cmdstanpy==1.2.4`

### Node（backend）
- [x] uuid（`node:crypto randomUUID`，無需額外套件）

### DB Migrations
- [x] `0009_demand_forecasts.sql`
- [x] `0010_forecast_jobs.sql`
- [x] `0011_tenants.sql`
- [x] `0012_add_tenant_id.sql`（12 張業務表 tenant_id + FK + index）
- [x] `0013_tenant_onboarding.sql`（contact_email / timezone / onboarded_at）

### 環境變數
- [x] `FORECAST_WEEKS_AHEAD=12`
- [x] `FORECAST_MIN_DATA_WEEKS=8`
- [x] `FORECAST_JOB_LEASE_SECONDS=900`
- [~] `TENANT_PROVISION_SECRET=<secret>`（Sprint 4C PR-7；**決策：暫緩**，provision 目前公開，未來需保護時加 `X-Provision-Secret` header check）
- [x] `AI_INTERNAL_SCOPES=analytics.read,forecast.generate`

---

## 風險追蹤（持續更新）

- [ ] Prophet 在 Windows 安裝失敗 → 全程在 Docker 內 build ✅ 已驗證
- [ ] tenant_id migration 破壞 LWW sync 邏輯 → staging 先跑 + rollback script（本地已驗，staging 待 Docker）
- [ ] 歷史訂單 < 8 週無法 fit → seed 26 週歷史資料 + `insufficient_data` flag
- [ ] 多副本重複跑 forecast → `forecast_jobs` + lease / advisory lock ✅ 已驗證
- [ ] WAF 誤擋正常 API → observe 7 天再切 enforce
- [ ] internal token 外洩 → scope 拆分 + internal-only network + rotation runbook
- [ ] analytics / AI read endpoint 漏加 tenant filter → tenant-aware repository + 負向測試 + checklist ✅ 已完成

---

*配套文件：`docs/NJ_Stream_ERP Phase4 PRD v1.0.md`*
