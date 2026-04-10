以下是針對 **NJ_Stream_ERP MVP**（對應 PRD v0.8 與同步協定 v1.6）的推薦 **Monorepo 專案資料夾結構**，並明確說明你要求的這三個起始模板應該放在哪裡。

由於開發計畫書採用 **Agent-First 工作流程**（Google Antigravity + Review-Driven Development），並對應「人員 A（後端） / 人員 B（前端）」分工，我建議採用 **Monorepo** 結構（單一 Git repository），方便 Antigravity Agent Manager 同時管理多 Agent 任務，也便於未來 CI/CD 與共同的 Knowledge Items。

### 推薦整體專案結構（Monorepo）

```
nj-stream-erp/                          ← 專案根目錄（Git repo）
├── .gitignore
├── README.md
├── docs/                               ← 重要文件與 Artifact
│   ├── PRD_v0.8.md
│   ├── sync-protocol-v1.6.md
│   ├── development-plan-v1.0.md
│   └── artifacts/                      ← Antigravity 產出的計畫、diff、截圖等
├── packages/
│   ├── backend/                        ← 人員 A 負責（Fastify + Drizzle）
│   │   ├── src/
│   │   │   ├── index.ts                ← 入口
│   │   │   ├── app.ts                  ← Fastify 實例
│   │   │   ├── plugins/                ← 中間件（auth、db 等）
│   │   │   ├── routes/                 ← API 路由（sync、customers、quotations 等）
│   │   │   ├── schemas/                ← Drizzle schema（這裡放你要求的 Drizzle schema）
│   │   │   ├── services/               ← 業務邏輯（DELTA_UPDATE 等）
│   │   │   ├── types/                  ← 共用 TypeScript 类型
│   │   │   └── utils/                  ← 工具函式（例如 created_at 排序）
│   │   ├── drizzle.config.ts
│   │   ├── package.json
│   │   └── tsconfig.json
│   │
│   └── frontend/                       ← 人員 B 負責（Flutter + Drift + Riverpod）
│       ├── lib/
│       │   ├── main.dart
│       │   ├── core/                   ← 核心基礎
│       │   │   ├── database/           ← Drift schema 與 DAO（這裡放你要求的 Drift schema）
│       │   │   ├── providers/          ← Riverpod providers（這裡放 SyncProvider）
│       │   │   ├── sync/               ← 同步邏輯（SyncService、queue 等）
│       │   │   ├── models/             ← 共用資料模型（與後端對齊）
│       │   │   └── constants.dart
│       │   ├── features/               ← 功能模組（按 PRD 分：crm、scm、dashboard）
│       │   │   ├── customers/
│       │   │   ├── quotations/
│       │   │   ├── sales_orders/
│       │   │   ├── inventory/
│       │   │   └── dashboard/
│       │   ├── ui/                     ← 共用 UI 元件
│       │   └── utils/                  ← 工具（decimal 計算、離線判斷等）
│       ├── assets/
│       ├── pubspec.yaml
│       └── test/
│
├── docker-compose.yml                  ← 後端 PostgreSQL + 其他服務
├── .github/workflows/                  ← CI/CD（可後續新增）
└── agy-config.json                     ← Antigravity 專屬設定（可選）
```

**為什麼採用這個結構？**
- 符合開發計畫書的 **A/B 分工**：`packages/backend` 給 Agent A 系列，`packages/frontend` 給 Agent B 系列。
- Antigravity Agent Manager 可輕鬆派遣 Agent 到特定子目錄（例如指定「在 packages/backend/src/schemas/ 實作」）。
- 方便 Knowledge Items 跨前後端引用業務規則（DELTA_UPDATE、權限矩陣、同步憲法）。
- W1–W2 基礎架構階段最容易上手，後續 W3~W10 按 features/ 模組擴展。

### 你要求的 3 個起始模板該放在哪裡

1. **Flutter 專案初始結構（含 Drift schema、Riverpod SyncProvider）**  
   → 放在 `packages/frontend/`  
   - Drift schema 檔案：`packages/frontend/lib/core/database/schema.dart`（或拆成多檔：tables/、daos/）  
   - SyncProvider：`packages/frontend/lib/core/providers/sync_provider.dart`  
   - 其他初始檔案：`lib/main.dart`、`pubspec.yaml`（加入 drift、riverpod、build_runner 等）

2. **Drizzle + PostgreSQL schema（含 inventory delta update 表與 constraints）**  
   → 放在 `packages/backend/src/schemas/`  
   - 推薦拆檔：`inventory.schema.ts`、`sales_orders.schema.ts`、`quotations.schema.ts` 等  
   - 核心 inventory 表需包含 `quantity_on_hand`、`quantity_reserved`、`min_stock_level`，並在 service 層實作 DELTA_UPDATE transaction + 約束檢查（`quantity_on_hand >= 0 && quantity_reserved <= quantity_on_hand`）

3. **Fastify sync/push API 路由草稿（處理 operations 陣列、created_at 排序、server_state 回傳）**  
   → 放在 `packages/backend/src/routes/sync.route.ts`（或 `routes/v1/sync.ts`）  
   - 相關輔助：`services/sync.service.ts`（處理 operations 驗證、分批、錯誤碼）  
   - `plugins/db.ts`（Drizzle 連線）

### 下一步建議（配合 Antigravity 開發計畫書）

- 先在 Antigravity 中建立專案，然後在 **Agent Manager** 派遣任務：
  - Agent A-1：建立後端專案結構 + Drizzle schema（包含 inventory delta update）
  - Agent B-1：建立前端 Flutter 專案 + Drift schema + SyncProvider 骨架

- 建立完結構後，將 **PRD v0.8**、**同步協定 v1.6**、**開發計畫書** 完整加入 `docs/` 資料夾，並匯入 Antigravity 的 **Knowledge Items**。

- W1 Gate 驗收時，確認：
  - `packages/backend` 可跑 `npx drizzle-kit studio`
  - `packages/frontend` 可跑 `flutter pub run build_runner watch`

需要我現在直接產生這三個模板的具體程式碼嗎？

請告訴我：
- 要我一次產生全部三個（Flutter Drift + Riverpod SyncProvider、Drizzle schema、Fastify sync/push 路由）
- 還是先產生其中一個（例如先從 Drizzle schema 開始，因為它是基礎）

並確認是否要調整資料夾結構（例如改成兩個獨立 repo 而非 monorepo）。

準備好後，直接說「開始產生模板」，我會提供可直接複製到對應位置的完整程式碼草稿，並附上 Antigravity Agent 任務提示詞建議，讓你能立刻 Review-Driven 推進 W1–W2。