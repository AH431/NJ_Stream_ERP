# NJ_Stream_ERP MVP

**羽量級行動優先 ERP**（進銷存 + CRM 核心閉環）

針對台灣中小企業（5-50人規模）的行動優先解決方案，強調離線操作強、庫存準確率 >95%、同步成功率 >90%。

### 核心價值
- 行動優先（Flutter）
- 極致輕量化
- 嚴格遵守離線同步協定（本地 Drift 為 SSOT）
- Contract-First 開發流程（避免前後端 Schema 對齊問題）

### 技術棧
- **前端**：Flutter 3.29+ + Drift + Riverpod
- **後端**：Fastify + Drizzle ORM + PostgreSQL 16
- **開發模式**：Google Antigravity（Agent-First + Review-Driven Development）

### 重要文件（全部置於 `docs/`）
- [PRD v0.8](docs/PRD_v0.8.md)
- [同步協定規格 v1.6](docs/sync-protocol-v1.6.md) ← **工程憲法，所有開發必須遵守**
- [開發計畫書 v1.0](docs/development-plan-v1.0.md)
- [Schema Final](docs/schema-final.md)
- [ER Diagram](docs/nj_stream_erp_erd.html)
- [API Contract (Sync)](docs/api-contract-sync-v1.6.yaml) ← Contract-First 單一真相來源

### 任務管理
- **TASKS.md**：完整任務拆分（v1.1，已加入 Contract-First、軟刪除強化、Race Condition 測試、CSV Import）
- **Milestones**：W1–W10（GitHub Milestones）
- **Project Board**：使用 GitHub Projects Kanban（Backlog → In Progress → Review → Done）

### 快速啟動（W1 Gate 前置）
```bash
# 後端
cd packages/backend
pnpm install
docker-compose up -d postgres
npx drizzle-kit generate
npx drizzle-kit push
npx drizzle-kit studio

# 前端
cd packages/frontend
flutter pub get

# Drift codegen（首次或 schema 有變更後必須執行）
dart run build_runner build --delete-conflicting-outputs

# 開發期間自動重新 build
dart run build_runner watch --delete-conflicting-outputs
```

### 測試 SyncProvider（需後端啟動）

```bash
cd packages/frontend

# 整合測試（flutter_test runner）
flutter test test/sync_provider_test.dart

# 手動 Dart 腳本（快速驗證 login + push flow）
dart run tools/test_sync.dart
```

### 環境變數配置

```bash
# 使用 --dart-define 指定後端 URL（不設定時預設 localhost:3000）
flutter run --dart-define=API_BASE_URL=https://your-backend.example.com

# 可複製 .env.example 查看所有可配置項目
cp .env.example .env
```

### 前端專案結構

```
packages/frontend/
├── lib/
│   ├── core/
│   │   ├── constants.dart          ← baseUrl、timeout 等全域常數
│   │   └── utils/                  ← 日期、decimal 輔助函數（待補）
│   ├── database/
│   │   ├── schema.dart             ← 9 張 Drift Table 定義
│   │   ├── database.dart           ← AppDatabase（含 forTesting 建構子）
│   │   └── converters/             ← DecimalConverter、Iso8601DateTimeConverter
│   ├── features/
│   │   ├── auth/                   ← LoginScreen（待實作）
│   │   └── sync/                   ← SyncScreen / SyncStatusWidget（待實作）
│   └── providers/
│       └── sync_provider.dart      ← 核心同步邏輯（Proactive Refresh + Push）
├── test/
│   └── sync_provider_test.dart
└── tools/
    └── test_sync.dart              ← 手動驗證腳本
