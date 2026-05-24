# NJ Stream ERP Phase 4 PRD v1.1
# 需求預測引擎 × 生產就緒 × 首位客戶入門

> **版本**：v1.1 — 2026-05-17
> **核心優先序**：系統穩定封關 > 資安與隔離基礎 > AI 需求預測 MVP > 客戶入門
> **輸出路徑**：`docs/NJ_Stream_ERP Phase4 PRD v1.0.md`

---

## 一、Phase 4 定位與目標

### 1.1 前一 Phase 交接狀態

Phase 3 完成：PR-1~PR-10 全部封閉（2026-04-29），RAG Phase 2 驗收通過（49/49），5 項
Critical/High 安全修正已上線（2026-05-16）。架構圖已輸出（architecture.json v1.1.0）。

**未關閉事項（Phase 3 遺留）**：

| 項目 | 風險 |
|---|---|
| S-1~S-5 靜態 AI 聊天手機 E2E | 中 |
| SourceCard 靜態路由手機驗收 | 低 |
| 雙裝置 race condition 實測 | 高 |
| Cloudflare WAF 啟用（需網域） | 高 |
| FCM 推播 E2E | 中 |
| 安全審查 Medium 項目 #6~#12 | 中 |

### 1.2 Phase 4 主題：「首位客戶就緒（Customer-Zero Ready）」

Phase 4 的終點不是「更多功能」，而是：

> 有一位真實台灣中小製造商能用 NJ Stream ERP 管理自己的庫存與訂單，
> 並透過 AI 需求預測功能得到庫存補貨建議——以此換取真實需求資料。

**核心策略原則（來自 Manish, eBay, 2026-05-17 導師建議）**：
- 先找客戶，再擴功能——不要先建系統再找客戶
- 每個模組先定義「問題→輸入→輸出→業務邏輯→儲存」再動工
- 最小可行路徑：Claude 業務邏輯 + Supabase/PostgreSQL 後端

### 1.3 Phase 4 三大 Sprint

| Sprint | 主題 | 目標 | PR 數 |
|---|---|---|---|
| **4A** | 生產封關 | 關閉 Phase 3 遺留、修 Medium 安全、部署網域、補觀測性 | PR-1, PR-2 |
| **4B** | 需求預測 MVP | 在 tenant-aware 與可恢復排程前提下建立 AI 差異化核心功能 | PR-3, PR-4, PR-5 |
| **4C** | 多租戶基礎 | 讓第二個客戶能安全上線 | PR-6, PR-7 |

### 1.4 Phase 4 不可妥協約束

- 不新增任何「僅靠開發者記得加 where」才能成立的資料隔離設計。
- 不新增任何「只要多開一個副本就會重複執行」的排程或背景工作。
- 不新增任何只有單一共享 secret、沒有審計與最小權限邊界的 internal API。
- 不以「手動測 10 次」、「5 題 golden set」作為 production-ready 的唯一證明。

---

## 二、系統架構擴充（Phase 4 新增）

### 2.1 需求預測資料流

```
[銷售訂單歷史 sales_orders + order_items]
        │
        │ 每晚 00:00 / 手動觸發
        ▼
[ai_service /forecast/generate  (FastAPI)]
  ├── 拉取各產品過去 52 週銷售量（週彙總）
  ├── Prophet model.fit() per product
  ├── model.predict() → 未來 12 週
  └── 寫入 demand_forecasts 表
        │
        ▼
[Fastify GET /api/v1/analytics/forecast]
  ├── 查 demand_forecasts 表
  └── 回傳 { productId, sku, forecasts: [{weekStart, qty, lower, upper}] }
        │
   ┌────┴─────┐
   ▼          ▼
[Flutter]   [AI Chat]
Dashboard   get_demand_forecast(sku, weeks)
ForecastTab tool call → SourceCard 顯示
```

### 2.2 多租戶資料隔離策略（Sprint 4C）

採用「應用層 tenant_id 注入」，不做 PostgreSQL schema 分割：

```
tenants 表
  id | name | slug | plan | createdAt

所有業務表加 tenant_id 欄（外鍵 → tenants.id）
JWT payload: { userId, role, tenantId }
Backend middleware: 所有 query 自動注入 WHERE tenant_id = req.user.tenantId
```

**設計理由**：
- Schema 分割對 Drizzle ORM 不友善，遷移風險高
- Row-level 注入可漸進導入，existing data 遷移為 tenant_id=1

### 2.3 穩定性與資安基線（新增）

#### A. Tenant 隔離不是 middleware 宣告，而是查詢層強制規則

- `tenantId` 必須進入 JWT payload、request context、service method signature。
- 所有業務查詢必須經過 tenant-aware repository / query helper；禁止新增繞過 tenant guard 的 raw SQL。
- migration 完成前，不得上線第二個 tenant。

#### B. 預測任務必須可去重、可恢復、可審計

- 不採用單純 in-process `node-cron` 作為唯一排程機制。
- 排程必須具備 job lease / advisory lock / DB job row 三者之一，保證同一 tenant + model_version + week window 不重複執行。
- 每次 forecast run 必須寫入 job log：開始時間、結束時間、tenantId、產品數、跳過數、錯誤摘要。

#### C. Internal API 必須是最小權限

- `X-Internal-Token` 只能用於 service-to-service read / forecast job，不可直接授予一般管理操作。
- internal token 必須區分 scope，至少拆為 `analytics.read` 與 `forecast.generate`。
- 所有 internal endpoint 都要有 audit log 與 rate limit，且禁止對 public internet 直接暴露。

#### D. 驗收需涵蓋故障情境

- 要有 upstream timeout、partial failure、retry、重複執行、client disconnect、migration rollback drill 的測試或演練。
- production gate 必須包含 observability：structured log、error rate、job duration、queue lag 或等價指標。

---

## 三、Sprint 4A：生產封關

### PR-1：Phase 3 遺留驗收 + Medium 安全修正

**目標**：關閉所有未驗收項目；修補 Medium 安全問題 #6~#12；補上 production 最低觀測性與壓力驗證。

#### M1.1 靜態 AI 聊天手機 E2E（S-1~S-5）

- **問題**：S-1~S-5 只在 Python CLI 驗過 retriever，手機 App 全路徑未驗
- **輸入**：啟動 tunnel + ai_service + 手機 App
- **輸出**：5 題靜態問答在手機端有正確回覆，且無 SourceCard 出現
- **業務邏輯**：static 路由不觸發 tool_call SSE，AiProvider 不產生 source
- **驗收**：5/5 通過，SourceCard 數量 = 0

#### M1.2 雙裝置 race condition 實測

- **問題**：庫存 `SELECT ... FOR UPDATE` 已加，但未用兩台裝置實際驗證
- **輸入**：兩台 Android 同時送 RESERVE 同一批次庫存
- **輸出**：一台 200 成功、一台 409 INSUFFICIENT_STOCK，DB 無超賣
- **業務邏輯**：`sync.service.ts` 庫存鎖定邏輯
- **驗收**：至少 100 次重複實測 0 次超賣，且保留測試腳本 / 操作紀錄

#### M1.3 Medium 安全修正（#6~#12）

| # | 問題 | 修法 |
|---|---|---|
| 6 | FCM sendEachForMulticast 無 500-token 分批 | `fcm.service.ts`：chunk tokens array，loop 送 |
| 7 | bypassDuplicateCheck 無授權控制 | `sync.service.ts`：加 `role === 'admin'` guard |
| 8 | isActive 停用帳號 access token 1h 視窗 | `auth.plugin.ts`：verifyJwt 加 DB isActive check（加 Redis 或 1min TTL 快取） |
| 9 | AnomalyScanner 並發可重複插入 | `anomaly_scanner.service.ts`：anomalies 表加 `UNIQUE(entity_type, entity_id, alert_type) WHERE is_resolved = FALSE`（partial unique index）；所有 INSERT 補 `ON CONFLICT DO NOTHING` |
| 10 | confirmedAt/shippedAt 由 client 控制 | `sync.service.ts`：改為 server-side `new Date()` 注入，strip client payload |
| 11 | Logout 拒絕過期 token | `auth.route.ts`：改 `jwt.decode` |
| 12 | getSecret() 無 null guard | `auth.route.ts`：加 null check，throw 明確 500 |

#### M1.4 生產觀測性基線

- **問題**：目前 PRD 缺少排障與趨勢觀測要求，上線後難以追查 token、job、推播、AI timeout 問題
- **輸入**：backend / ai_service 現有 log 與 audit log
- **輸出**：最少要能觀測 API 5xx、AI upstream timeout、forecast job duration、FCM success/failure count
- **業務邏輯**：補 structured log key，重要背景工作寫 audit / job log
- **驗收**：能用單一 requestId 或 jobId 追到完整執行鏈

**測試需求**：
- vitest 全綠（目前 52 tests），安全修正各項加對應 unit test
- race condition 壓力驗證結果存檔
- AI / FCM / auth 失敗情境至少各 1 組負向測試

---

### PR-2：生產部署（網域 + Cloudflare WAF + Docker prod 驗證）

**目標**：從 Cloudflare Quick Tunnel（臨時）遷移到固定網域，WAF 正式啟用，並確保 internal service 不暴露到 public edge。

#### M2.1 網域購買與 DNS 設定

- **問題**：目前用 `*.trycloudflare.com` 臨時 tunnel，APK 每次需重建
- **輸入**：購買 `njstream.tw`（或類似）+ Cloudflare DNS
- **輸出**：固定 API base URL，APK 不再需要因 tunnel 重啟而重建
- **業務邏輯**：Cloudflare Tunnel → 固定 hostname 設定
- **儲存**：`packages/frontend/lib/config/app_config.dart` 更新 prodUrl 常數
- **驗收**：`curl https://api.njstream.tw/health` → `{"status":"ok"}`

#### M2.2 Cloudflare WAF 正式啟用

- **問題**：`verify_waf.ps1` 已備妥，但需網域才能啟用
- **輸入**：`cloudflare-waf-setup.md` 設定步驟
- **輸出**：WAF 規則啟用、`verify_waf.ps1` 全部 pass（401 不計為 WAF 攔截）
- **驗收**：`verify_waf.ps1` 輸出 `WAF PASS`，且先 observe 7 天，再切 enforce

#### M2.3 FCM 推播 E2E 驗收

- **問題**：AnomalyScanner → FCM → 手機通知完整路徑未實機驗收
- **輸入**：實機 + Firebase Console Service Account
- **輸出**：anomaly 觸發 → 手機收到推播通知
- **驗收**：兩次觸發，兩次手機收到通知

#### M2.4 網路邊界確認

- **問題**：ai_service 與 internal analytics endpoint 若對外暴露，單一 internal token 外洩風險過高
- **輸入**：Docker / tunnel / reverse proxy 設定
- **輸出**：public edge 只暴露 Flutter / public API 所需路徑；ai_service 與 internal-only route 僅內網可達
- **驗收**：由外部網路無法直接存取 `/forecast/*` 與 internal-only endpoint

---

## 四、Sprint 4B：需求預測 MVP

### PR-3：需求預測引擎（ai_service 擴充）

**目標**：在 ai_service 新增 tenant-aware、可審計、可恢復的需求預測端點，計算各產品未來 12 週需求。

#### 工程設計拆解

| 維度 | 規格 |
|---|---|
| **問題** | 倉管人員不知道何時補貨、補多少，靠經驗猜測導致缺貨或積貨 |
| **輸入** | `tenantId` + `productId`（或全部），過去 52 週 `order_items.quantity` × `confirmed` 訂單彙總 |
| **輸出** | 各 product 未來 12 週預測銷量（週單位）+ 信賴區間 |
| **業務邏輯** | Prophet 週頻率 fit → predict；資料 < 8 週者標記 `insufficient_data` 跳過；每次 run 具 idempotency key 與 job log |
| **儲存** | `demand_forecasts` 表（見 §4.1） |

#### 4.1 新增資料表：`demand_forecasts`

```sql
CREATE TABLE demand_forecasts (
  id          SERIAL PRIMARY KEY,
  product_id  INTEGER NOT NULL REFERENCES products(id),
  tenant_id   INTEGER NOT NULL REFERENCES tenants(id),
  week_start  DATE NOT NULL,               -- 每週一
  forecast_qty NUMERIC(10,2) NOT NULL,
  lower_bound  NUMERIC(10,2),
  upper_bound  NUMERIC(10,2),
  model_version VARCHAR(20) DEFAULT 'prophet-v1',
  generated_at TIMESTAMPTZ DEFAULT NOW(),
  run_id       UUID NOT NULL,
  UNIQUE(tenant_id, product_id, week_start, model_version)
);
```

```sql
CREATE TABLE forecast_jobs (
  id               UUID PRIMARY KEY,
  tenant_id        INTEGER NOT NULL REFERENCES tenants(id),
  requested_by     INTEGER,
  trigger_type     VARCHAR(20) NOT NULL,     -- manual / scheduled / replay
  status           VARCHAR(20) NOT NULL,     -- pending / running / success / failed
  weeks_ahead      INTEGER NOT NULL,
  model_version    VARCHAR(20) NOT NULL,
  started_at       TIMESTAMPTZ,
  finished_at      TIMESTAMPTZ,
  lease_expires_at TIMESTAMPTZ,             -- 分散式 lease；到期後可補跑
  generated_cnt    INTEGER DEFAULT 0 NOT NULL,
  skipped_cnt      INTEGER DEFAULT 0 NOT NULL,
  error_summary    TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW() NOT NULL
);
```
> **注意**：`tenant_id REFERENCES tenants(id)` 需在 Sprint 4C `tenants` 表建立後才能加 FK；PR-3 migration 先建欄位，Sprint 4C M6.2 補 FK 約束。

#### 4.2 ai_service 新增端點

```
POST /forecast/generate
  Body: { tenantId: number, productIds?: number[], weeksAhead?: number, triggerType?: 'manual' | 'scheduled' }
  Auth: X-Internal-Token
  Flow:
    0. 建立 / claim forecast_jobs row；若已有 running job 則拒絕重複執行
    1. 呼叫 Fastify GET /api/v1/analytics/sales-history?tenantId=T&weeks=52
    2. 按 productId 彙總週銷量 → DataFrame
    3. 資料 < 8 週 → 記錄 skipped_products，跳過
    4. Prophet fit + predict
    5. 寫入 demand_forecasts（UPSERT on model_version）
    6. 更新 forecast_jobs success / failed 與統計
  Response: { runId, generated: number, skipped: number[], durationMs: number }

GET /forecast?tenantId=T&productId=X&weeks=12
  Auth: X-Internal-Token
  Response: { productId, sku, forecasts: [{weekStart, qty, lower, upper}] }
```

#### 4.3 Fastify 新增端點（後端代理）

```
GET /api/v1/analytics/forecast?productId=X&weeks=12
  Auth: JWT（warehouse / admin / sales）
  → 由 request.user.tenantId 代理到 ai_service GET /forecast

POST /api/v1/analytics/forecast/generate
  Auth: JWT（admin only）
  → 以 request.user.tenantId 代理到 ai_service POST /forecast/generate

GET /api/v1/analytics/sales-history?weeks=52
  Auth: X-Internal-Token（僅 ai_service 呼叫，scope=analytics.read）
  → 查單一 tenant 的 sales_orders JOIN order_items，回傳週彙總
```

#### 4.4 依賴安裝

```
packages/ai_service/requirements.txt 新增：
  prophet==1.1.5
  pandas==2.2.2
  cmdstanpy==1.2.4   ← prophet dependency
```

**測試需求**：
- `test_forecast_engine.py`：4 組 fixture（正常/少資料/單品/空）
- `test_forecast_route.py`：POST generate + GET forecast mock 驗收
- 重複觸發同一 tenant job 時只能有 1 個 running
- 單一產品失敗不影響其他產品寫入，job status 要能反映 partial failure

---

### PR-4：Fastify 排程觸發器

**目標**：建立可去重、可恢復的排程觸發機制；若正式 scheduler 未完成，先以手動 + 安全回補模式上線。

#### 工程設計拆解

| 維度 | 規格 |
|---|---|
| **問題** | 需求預測需每日更新才有意義，手動觸發不可靠 |
| **輸入** | 外部 scheduler 或單一 worker 觸發 |
| **輸出** | demand_forecasts 表每日更新，且不因多副本重複執行 |
| **業務邏輯** | 優先用單獨 worker / external scheduler；執行前先 claim forecast_jobs |
| **儲存** | `forecast_jobs` + `demand_forecasts` |

```typescript
// packages/backend/src/services/forecast_scheduler.service.ts
// Pseudocode: scheduler only enqueues / claims; worker executes exactly once.
for (const tenant of activeTenants) {
  enqueueForecastJob({
    tenantId: tenant.id,
    triggerType: 'scheduled',
    weeksAhead: 12,
    modelVersion: 'prophet-v1',
  })
}
```

**驗收**：
- 同時啟動兩個 backend / worker instance，單一 tenant 同一時窗只會產生 1 個成功 job
- worker 中途 crash 後可由 lease timeout / replay 機制補跑
- 手動觸發 `POST /api/v1/analytics/forecast/generate`（Admin）後有對應 job log 與 forecast 資料

---

### PR-5：需求預測 UI（Dashboard + 手機）

**目標**：讓倉管人員能在 App 看到補貨建議，AI 聊天能回答「X 產品幾週後需要補貨？」

#### 5.1 Dashboard 新增預測卡片

```
ForecastSummaryCard
  ├── 本週低於安全庫存且預測上升 → 紅色補貨警示（Top 3 產品）
  ├── 未來 4 週預測需求量 vs 現有庫存
  └── 點擊 → 跳轉 ProductForecastScreen
```

#### 5.2 ProductForecastScreen（新 Screen）

```
ProductForecastScreen
  ├── ProductSelector（DropdownButton）
  ├── ForecastChart（12 週折線圖，含信賴區間帶）
  │     使用 fl_chart LineChart，陰影填滿 lower~upper
  ├── ForecastTable（週次 / 預測量 / 建議採購量）
  │     建議採購量 = max(0, forecastQty - currentStock)
  └── ExportButton → PDF 報表（複用現有 PDF 模組）
```

#### 5.3 AI 工具擴充：`get_demand_forecast`

```python
# packages/ai_service/src/tools/erp_tools.py 新增

async def get_demand_forecast(sku: str, weeks: int = 8) -> dict:
    """
    問題：使用者問某產品未來需求
    輸入：sku, weeks（預設8週）
    輸出：{ sku, forecasts: [{weekStart, qty}], reorderAlert: bool }
    業務邏輯：查 demand_forecasts → 對比現有庫存 → 判斷是否需補貨
    """
    ...
```

query_router 新增 pattern：`需要補貨|下週需求|預測庫存|幾週後缺貨` → `dynamic`

**測試需求**：
- Widget test：ForecastDetailScreen render + empty state
- Golden eval 新增 5 題預測類問題（demand forecast golden set）

---

## 五、Sprint 4C：多租戶基礎

### PR-6：資料庫多租戶遷移

**目標**：在所有業務表加 `tenant_id`，existing data 遷移為 tenant_id=1，不破壞現有功能。

#### 工程設計拆解

| 維度 | 規格 |
|---|---|
| **問題** | 第二個客戶上線時資料會互漏，現在是 single-tenant |
| **輸入**  | 現有 12 張業務表，全部 data 歸屬 tenant_id=1（'demo'） |
| **輸出** | 所有業務查詢在程式結構上被強制帶入 tenant 條件，資料完整隔離 |
| **業務邏輯** | 應用層強制注入，不用 PostgreSQL RLS；但不得依賴人工記憶補 where |
| **儲存** | 新增 `tenants` 表；各表加 `tenant_id INTEGER NOT NULL DEFAULT 1` |

#### 6.1 新增資料表：`tenants`

```sql
CREATE TABLE tenants (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  slug       VARCHAR(50) UNIQUE NOT NULL,   -- URL-safe，如 'demo', 'abc-mfg'
  plan       VARCHAR(20) DEFAULT 'trial',   -- trial / starter / pro
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO tenants (id, name, slug) VALUES (1, 'Demo Company', 'demo');
```

#### 6.2 Drizzle Migration（0008_add_tenant_id.ts）

各表加 `tenant_id`，步驟：
1. `ALTER TABLE xxx ADD COLUMN tenant_id INTEGER NOT NULL DEFAULT 1`
2. `ALTER TABLE xxx ADD CONSTRAINT fk_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)`
3. 更新 Drizzle schema files

**遷移護衛（依 migrate_with_log.ps1 模式）**：
- 遷移前備份
- 遷移後驗證 row count 不變
- existing 資料全部 = tenant_id 1

#### 6.3 JWT 擴充

```typescript
// JWT payload 新增 tenantId
interface JwtPayload {
  userId: number
  role: 'admin' | 'sales' | 'warehouse'
  tenantId: number   // ← 新增
}
```

#### 6.4 Backend Query Guard（取代單純 middleware 幻覺）

```typescript
// request 只負責攜帶 tenantId，不保證資料層安全
fastify.addHook('onRequest', async (req) => {
  if (req.user) req.tenantId = req.user.tenantId
})

// 真正的保護必須在 repository / query helper
listProducts({ tenantId, ...filters })
getInventory({ tenantId, productId })
getSalesHistory({ tenantId, weeks })
```

**實作要求**：
- 新增 tenant-aware repository / query helper，所有業務 route 只能走這一層
- 對現有 raw SQL 路由逐一補 tenant filter，尤其 analytics / dashboard / AI read endpoints
- 在 lint / code review checklist 明文禁止新增未帶 tenant 條件的業務查詢

**測試需求**：
- tenant_id=1 的 query 不能看到 tenant_id=2 的資料（cross-tenant isolation test）
- 遷移後 row count 100% 保留
- 至少 5 類高風險 API 做負向測試：customers、products、inventory、analytics、AI tool-backed read
- migration rollback script 演練一次

---

### PR-7：客戶入門流程（Admin Onboarding）

**目標**：讓新客戶能在 30 分鐘內完成初始化設定，不需工程師介入。

#### 工程設計拆解

| 維度 | 規格 |
|---|---|
| **問題** | 新客戶沒有 UI 可以設定自己的公司資料、用戶、初始庫存 |
| **輸入** | Admin 登入後的引導流程 |
| **輸出** | 完成 onboarding 後：公司名稱設定、至少一個倉管帳號、初始產品匯入 |
| **業務邏輯** | 3 步驟引導；完成後隱藏 onboarding banner |
| **儲存** | `tenants.onboarding_completed_at`（新增欄位） |

#### 7.1 OnboardingBanner（Flutter）

```
OnboardingBanner（首頁 Dashboard 頂部，完成後消失）
  Step 1：設定公司名稱 → PATCH /api/v1/tenant
  Step 2：建立第一個倉管帳號 → POST /api/v1/users
  Step 3：匯入產品 CSV → 跳轉 ImportScreen（複用現有）
  完成：PATCH /api/v1/tenant { onboardingCompletedAt: now }
```

#### 7.2 Tenant Admin API

```
GET  /api/v1/tenant            ← 查本 tenant 資料（Admin only）
PATCH /api/v1/tenant           ← 更新 name / onboardingCompletedAt
POST /api/v1/tenant/provision  ← 超級管理員建立新 tenant（seed 初始 admin 帳號）
```

**驗收門檻**：
- 新 tenant 從零到「能用 AI 查庫存」< 30 分鐘
- 不需工程師直接操作 DB

---

## 六、驗收門檻彙整

### Phase 4 整體 Gate（可演示給第一個客戶）

| 類別 | 條件 |
|---|---|
| **穩定性** | vitest 全綠；race condition 100+ 次 0 次超賣；WAF pass；forecast job 可重跑且不重複寫入 |
| **功能** | 需求預測 12 週圖表可見；補貨警示正確觸發；manual replay 可補 forecast |
| **AI** | `get_demand_forecast` golden eval 5/5；query router 新 pattern 覆蓋；upstream timeout 有明確錯誤路徑 |
| **多租戶** | cross-tenant isolation test pass；遷移 row count 100%；高風險 API 負向測試全綠 |
| **入門** | 新 tenant onboarding < 30 分鐘，zero engineering intervention |
| **生產** | 固定網域可存取；FCM 推播實機通過；internal endpoint 不對外暴露；可由 requestId / jobId 追蹤 |

---

## 七、風險清單

| 風險 | 機率 | 衝擊 | 緩解 |
|---|---|---|---|
| Prophet 安裝在 Windows 失敗（C++ build tools） | 中 | 高 | Docker 內安裝，ai_service 已 Dockerized |
| tenant_id migration 破壞 LWW sync 邏輯 | 中 | 高 | 遷移在 staging 先跑，加 rollback script |
| 歷史訂單資料不足（< 8 週）無法 fit | 高 | 中 | seed 補 26 週歷史資料；insufficient_data flag 不 crash |
| 需求預測每日排程在多副本重複執行 | 中 | 高 | 使用 `forecast_jobs` + lease / advisory lock；不以 in-process cron 當唯一來源 |
| WAF 誤擋正常 API 請求 | 低 | 高 | WAF 先以 observe 模式上線 7 天再切 enforce |
| internal token 外洩造成資料讀取或濫用預測資源 | 中 | 高 | token scope 拆分、internal-only network、audit log、rotation runbook |
| analytics / AI read endpoint 漏加 tenant filter | 中 | 高 | tenant-aware repository、負向測試、code review checklist |

---

## 八、技術依賴清單

**新增 Python 套件（ai_service）**：
```
prophet==1.1.5
pandas==2.2.2
cmdstanpy==1.2.4
```

**新增 Node 套件（backend）**：
```
uuid / queue / lock 機制（依最終 scheduler 實作決定）
```

**新增 DB 遷移**：
```
0008_anomalies_unique.sql  ← [已完成] anomalies partial unique index（Sprint 4A PR-1）
0009_demand_forecasts.sql  ← [已完成] demand_forecasts 表（Sprint 4B PR-3）
0010_forecast_jobs.sql     ← [已完成] forecast job ledger / lease（Sprint 4B PR-3）
0011_tenants.sql           ← tenants 表 + 各表 tenant_id 欄 + FK 補齊（Sprint 4C PR-6）
```
> `0008` slot 已被 `anomalies_unique` 佔用；多租戶遷移改編號 `0011`。

**新增環境變數**：
```
FORECAST_WEEKS_AHEAD=12          ← 預設預測週數
FORECAST_MIN_DATA_WEEKS=8        ← 資料不足跳過門檻
TENANT_PROVISION_SECRET=xxx      ← 超管建立新 tenant 的 secret
AI_INTERNAL_SCOPES=analytics.read,forecast.generate
FORECAST_JOB_LEASE_SECONDS=900
```

---

## 九、Sprint 時間估算

| Sprint | PR | 預計工期 |
|---|---|---|
| 4A | PR-1（遺留 + 安全 + 觀測）| 3–4 天 |
| 4A | PR-2（網域 + WAF + 邊界）| 1–2 天（含等待 DNS）|
| 4B | PR-3（預測引擎） | 4–5 天 |
| 4B | PR-4（排程 / job ledger） | 1–2 天 |
| 4B | PR-5（UI + AI 工具）| 3 天 |
| 4C | PR-6（多租戶 DB + query guard）| 3–5 天 |
| 4C | PR-7（入門流程）| 2 天 |
| **合計** | 7 PRs | **~4 週** |

---

*寫入路徑：`docs/NJ_Stream_ERP Phase4 PRD v1.0.md`*
