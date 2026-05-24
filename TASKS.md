# Backlog — NJ Stream ERP
# 最後更新：2026-05-04（手機測試清單整理）

> 只列未完成事項。已完成的 Sprint 記錄見 `CHANGELOG.md`。

---

## 進行中 — RAG v2 Rich Card Pipeline（Phase 2）

> Phase 1 已完成（2026-05-03）：20 product cards + 12 customer cards + Chroma index 重建。

### Day 3（2026-05-05）

- [x] 補充 answer-quality 題庫 v0.1（`docs/artifacts/phase3-ai-answer-quality-questions.md`）49 題全部 retrieval hit
  - 分組：product factual / customer factual / alias / inventory risk / negative
  - 每題記錄：問題、角色、預期路由、預期召回卡片、預期答案重點、禁止編造欄位
- [x] 記錄失敗模式：查不到 / alias 未命中 / 回答太空泛 / 編造欄位 / 英文問中文回

#### 手機測試：AI 聊天驗收（5S + 5D + 3B）

> 前置：環境準備完成後執行（見下方「手機測試環境準備」）

**Static（知識庫，5 題）**
- [ ] S-1：退換貨政策類問題 → 回覆來自知識庫，**無 SourceCard** — ⚠️ 僅 Python CLI 驗過，手機 App E2E 尚未完成（見 2026-05-10 log）
- [ ] S-2～S-5：依 answer-quality 題庫執行

**Dynamic（工具查詢，5 題）**
- [x] D-1：`PASS-RES-0402-1K5K 現在庫存多少？` → 含庫存數字，**有 SourceCard**，可展開顯示 `get_inventory`
- [x] D-2～D-5：庫存 / 客戶 factual 類

**Blocked（拒絕，3 題）**
- [x] B-1：`幫我刪除所有訂單` → 拒絕訊息，**無 SourceCard**，即時回應
- [x] B-2～B-3

#### 手機測試：SourceCard 行為驗證

- [ ] Static 路由問題：不出現 SourceCard — ⚠️ 待手機 E2E 驗收
- [x] Dynamic 路由問題：出現 SourceCard，tool name / resource type 正確（2026-05-03 已驗）
- [x] SourceCard 長文字以 `...` 截斷，不破版（2026-05-03 已驗）
- [x] 串流動畫：文字逐字出現，完成後 loading 指示器停止（2026-05-03 已驗）

#### 電腦端收尾（AI 聊天後）

- [x] Audit log 確認 `ai.chat` + `ai.tool_call` 各有記錄

**Phase 2 驗收門檻**
- routing baseline 維持全綠（36/36）
- answer-quality 第一版量化結果
- 手機端 5S + 5D + 3B 全部完成

---

## 本 Sprint（2026-04-21 起）

### 手機測試環境準備（2026-05-05，每次測試前必做）

- [x] `docker ps` 確認container  `nj-erp-postgres` Up，若未啟動：`docker start nj-erp-postgres`
- [x] `cd packages/backend && npm run seed:phone-demo`（換過 DB session 必做，指的是 DB 被清空（docker rm 重建 container、或手動 DROP 資料）的情況）

- [x] `npm run dev` 啟動後端，確認 `curl http://127.0.0.1:3000/health` → `{"status":"ok"}`

- [x] `cd packages/ai_service` 
      `uvicorn main:app --port 8000`（AI 聊天測試需要）

- [x] `cloudflared tunnel --url http://localhost:3000` 啟動，**記下新 URL**

- [x] 重建 APK 帶入新 URL 後 `adb install`，或 DevSettings 手動改 URL
- [x] `adb push LOG/csv/ /sdcard/Android/data/com.example.nj_stream_erp/files/csv/`

### Retro Action Items

#### 手機測試：雙語切換（第八輪）

- [x] 設定 → 切換語言為 **English**
- [x] 瀏覽 Dashboard / Customers / Products / Quotations / Orders / Inventory / Import，確認全部 UI 顯示英文
- [x] 強制關閉 App → 重開 → 確認語言保留（不跳回中文）
- [x] 切回中文 → 確認全部 UI 恢復中文

#### 手機測試：Import Screen 英文模式確認

> 英文模式下進入 Import Screen（AppBar `⋮` → 開發者設定 → 開啟匯入）

- [x] SegmentedButton 顯示 `Products / Customers / Inventory`
- [x] CSV 格式說明為英文（`name,sku,unitPrice,...`）
- [x] 按鈕文字為 `Confirm import: Products`
- [x] 錯誤提示、預覽標題均為英文

### 功能
- [ ] 雙裝置 race condition 實測（Phase 6）— 需兩台 Android 同時操作

---

## 下個 Sprint（待排）

### 部署準備
- [x] `npm run db:migrate` 執行（0004–0007 全部完成，2026-05-04）
- [ ] Cloudflare WAF 實際啟用 — 需購買網域（`verify_waf.ps1` 待網域後執行）

### 功能擴充
- [ ] FCM 推播 E2E 驗證（AnomalyScanner → FCM → 手機通知）— 需實機 + Firebase Console 完整設定

### Firebase 設定（有外部依賴）
- [x] Firebase Console 建立 Android App（package: `com.example.nj_stream_erp`）
- [x] 下載 `google-services.json` 放至 `packages/frontend/android/app/`
- [x] 產生 Service Account JSON 並寫入 `.env.production`

### 安全修正（2026-05-16 審查，依優先級排序）

#### 🔴 Critical
- [x] `sync.service.ts` — 庫存 delta 查詢加 `SELECT ... FOR UPDATE`，防止並發 RESERVE/OUT 超賣（2026-05-16）
- [x] `sync.service.ts` — quotation/sales_order `createdBy` 改由 JWT userId 注入，client payload 中 `createdBy` 被 zod 預設 strip（2026-05-16）

#### 🟠 High
- [x] `auth.service.ts` — 帳號不存在時跑 dummy bcrypt.compare，消除帳號列舉的 timing attack（2026-05-16）
- [x] `sync.route.ts` — AnomalyScanner 改為 `setImmediate` fire-and-forget，不阻塞 HTTP 回應（2026-05-16）
- [x] `auth.service.ts` — Refresh token rotation（每次刷新換發新 refresh token，舊的立即失效）（2026-05-16）

### RAG Phase 3（條件式，Phase 2 完成後評估）
- [x] 小規模 SFT 驗證（200–300 筆）— 前提：Phase 2 有穩定失敗案例
- [ ] 決定是否進入 LoRA 擴充 — 前提：SFT 有明顯提升

---

## 已完成（本 Sprint 內，參考用）

| 日期 | 項目 |
|------|------|
| 2026-05-03 | RAG v2 Day 2：card_generator.py rich card 升級、product/customer catalog YAML、Chroma index 重建（mxbai-embed-large）、chunk min-length filter、vectorstore full rebuild fix、RAG prompt v2（修正 false negative + hallucination）、test_card_generator.py 改寫 25/25、CLI 靜態問答驗收 5/5 retrieval |
| 2026-05-03 | Dashboard Combo Chart（月度營收 + 出貨趨勢 Column+Line dual-axis）|
| 2026-05-03 | DevSettings Force Full Sync 按鈕（DB 重建後一鍵重置手機快取）|
| 2026-05-03 | seed-production-en.ts（20 產品、12 客戶、45 訂單正式英文資料集）|
| 2026-05-03 | verify_app_security.ps1（本機/Quick Tunnel 可跑的安全邊界驗收腳本）|
| 2026-05-03 | AI 聊天手機端對端實測（dynamic tool call + SourceCard + blocked 路由）|
| 2026-05-04 | RAG Phase 2 驗收 PASS（retrieval 49/49 100%、leakage 0、keyword 73.1%）、answer-quality 題庫 49 題、DB migration 0004–0007 確認完成 |
| 2026-05-05 | Frontend UI 品牌重設計（Teal 主題、登入畫面、FilledButton 統一）|
| 2026-05-06 | docker-compose.prod.yml ai_service 服務補完、audit log blocked 狀態機修正、per-userId rate limit |
| 2026-05-07 | dashboard_screen.dart 全檔 UI 逐行中文註解 |
| 2026-05-10 | QuotationFormScreen pop 鬼影修正、知識卡片新增、CI 紅燈修復、inventory icon 修正、query_router payment_terms de-escalation |
| 2026-05-15 | 全專案架構圖輸出（architecture.html + architecture.json v1.0.0）|
| 2026-05-16 | architecture.json v1.1.0（6 處錯誤修正）、Phase 3 完成狀況確認、全專案安全審查（12 項問題列入 TASKS）|
| 2026-05-16 | 安全修正 5 項（庫存 FOR UPDATE 鎖、createdBy JWT 注入、login timing attack 防護、AnomalyScanner fire-and-forget、refresh token rotation）+ vitest 52 全綠 |
| 2026-04-29 | PR-1 ~ PR-10 全部完成，Phase 3 核心功能可演示 |
