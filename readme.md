# NJ Stream ERP — MVP

**羽量級行動優先 ERP**（進銷存 + CRM 核心閉環）

針對台灣中小企業（5–50 人規模）的行動優先解決方案。
強調離線操作、庫存準確率 >95%、同步成功率 >90%。

---

## 技術棧

| 層 | 技術 |
|----|------|
| 前端 | Flutter 3.29+ + Drift（local DB）+ Provider |
| 後端 | Fastify + Drizzle ORM + PostgreSQL 16 |
| 同步 | 自訂 Pull/Push 協定（LWW 衝突解法，Sync v1.6） |
| 資安 | JWT（HS256）+ bcrypt（rounds 12）+ Rate limiting + Cloudflare Tunnel |
| CI/CD | GitHub Actions + Dependabot |

---

## 已完成功能

- **認證**：登入 / 登出，JWT 持久化，角色（admin / sales / warehouse）
- **客戶管理**：CRUD、軟刪除、批次刪除、離線新增、客戶詳情頁 + 互動記錄（visit / call / email）
- **產品管理**：CRUD、軟刪除、批次刪除、離線新增
- **報價單**：新增、稅額切換、轉訂單、PDF 產生、Email 寄送
- **銷售訂單**：確認、預留庫存、出貨、取消，PDF 產生、Email 寄送
- **庫存管理**：快照列表（在庫 / 預留 / 可出貨）、低庫存警示、入庫操作
- **Dashboard**：待出貨訂單、低庫存警示、本月報價總額
- **CSV 批次匯入**：產品 / 客戶 / 庫存初始化（dart:io 資料夾掃描）
- **月結對帳單**：客戶維度，PDF 附件 Email 寄送
- **雙語 UI**：中文 / English 切換，語言設定持久化
- **Dev Settings**：執行期 API URL 設定、Cleanup、CSV Import 入口
- **離線 ID chain**：負數本地 ID + Push 後 FK remap（Issue #34）
- **AR（應收帳款）**：aging 分桶總覽、未收訂單明細、標記已付款 / 呆帳沖銷（Admin 專用）
- **分析儀表板（VIS）**：月營收趨勢、訂單狀態分佈、Top 產品排行、RFM 客戶分群、15 分鐘本機快取
- **異常推播（ALT）**：後端 AnomalyScanner 掃描 + FCM push、通知清單 + 嚴重度篩選 + 標記已解決

---

## 快速啟動

### 後端

```bash
cd packages/backend
npm install
docker-compose up -d postgres
npx drizzle-kit generate
npx drizzle-kit migrate
npm run dev
# 確認：Server listening at http://127.0.0.1:3000
```

### 前端

```bash
cd packages/frontend
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### 手機連線（Cloudflare Tunnel）

```bash
cloudflared tunnel --url http://localhost:3000
# 記下 URL → App 內 DevSettings → 貼上 URL → 儲存
```

### 推送 CSV 到手機

```bash
adb push LOG/csv/ /sdcard/Android/data/com.example.nj_stream_erp/files/csv/
```

---

## 文件索引

| 文件 | 路徑 | 說明 |
|------|------|------|
| PRD v0.8 | `docs/NJ_Stream_ERP MVP PRD v0.8.md` | 產品需求文件 |
| 同步協定 v1.6 | `docs/NJ_Stream_ERP MVP 同步協定規格 v1.6.md` | **工程憲法** |
| API Contract（Sync） | `docs/api-contract-sync-v1.6.yaml` | Contract-First 單一真相來源 |
| API Contract（Auth） | `docs/api-contract-auth.yaml` | 認證接口 |
| ADR-001 LWW 衝突解法 | `docs/adr/ADR-001-lww-conflict-resolution.md` | 架構決策記錄 |
| ADR-002 離線 ID chain | `docs/adr/ADR-002-offline-id-chain-remap.md` | 架構決策記錄 |
| ADR-003 CSV dart:io | `docs/adr/ADR-003-csv-import-dart-io.md` | 架構決策記錄 |
| Changelog | `CHANGELOG.md` | Sprint 維度完成記錄 |
| Backlog | `TASKS.md` | 未完成項目 |
| LOG 索引 | `LOG/INDEX.md` | 所有工作記錄導覽 |
| 手機測試指南 | `LOG/guides/phone-test-guide.md` | 8 輪完整測試流程 |

---

## 前端結構

```
packages/frontend/lib/
├── core/
│   ├── app_strings.dart        ← 雙語字串 ChangeNotifier（AppStrings）
│   ├── constants.dart          ← baseUrl、timeout 等全域常數
│   └── document_actions.dart   ← PDF 產生 / Email 寄送共用邏輯
├── database/
│   ├── schema.dart             ← Drift Table 定義
│   ├── database.dart           ← AppDatabase
│   ├── converters/             ← Decimal / DateTime 型別轉換器
│   └── dao/                    ← customer, product, quotation, sales_order,
│                                  inventory_items, interaction, remap
├── features/
│   ├── auth/                   ← LoginScreen
│   ├── dashboard/              ← DashboardScreen（KPI + Analytics 入口）
│   ├── customers/              ← List + Form + DetailScreen（互動記錄）
│   ├── products/               ← List + Form
│   ├── quotations/             ← List + Form
│   ├── sales_orders/           ← List + Reserve / Ship / Cancel Dialogs
│   ├── inventory/              ← List + StockIn Dialog
│   ├── ar/                     ← ArScreen（應收帳款，Admin 專用）
│   ├── notifications/          ← NotificationScreen（異常推播清單）
│   └── settings/               ← ImportScreen、DevSettingsScreen
├── providers/
│   ├── sync_provider.dart      ← 核心同步邏輯（Pull / Push / enqueue）
│   ├── analytics_provider.dart ← 分析資料拉取 + 15 分鐘快取
│   ├── anomaly_provider.dart   ← 異常掃描結果 + 標記已解決
│   ├── ar_provider.dart        ← 應收帳款 aging + 付款標記
│   └── rfm_provider.dart       ← RFM 客戶分群資料
└── services/
    └── fcm_service.dart        ← Firebase Cloud Messaging 初始化 + token 管理
```

---

## 已知限制 / 待辦

| 項目 | 說明 |
|------|------|
| Cloudflare WAF | 需購買網域，部署後設定 |
| Release APK | `--obfuscate --split-debug-info` 已測試可行，尚未正式發布 |
| 雙裝置 race condition（Phase 6） | 需兩台 Android 同時操作 |
| Push 通知完整整合 | FCM 基礎架構已完成；AnomalyScanner → FCM 推播路徑待 E2E 驗證 |

---

## 環境變數（`.env`）

```bash
cp .env.example .env
# 填入以下欄位
DATABASE_URL=postgresql://...
JWT_SECRET=...（至少 32 bytes）
GMAIL_USER=...
GMAIL_APP_PASSWORD=...
```