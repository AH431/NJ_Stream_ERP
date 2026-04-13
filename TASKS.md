# NJ_Stream_ERP MVP 任務拆分
**版本**：v1.1（2026/04/10 修正版）
**對應文件**：PRD v0.8、同步協定 v1.6、開發計畫 v1.0、Schema Final
**開發模式**：Google Antigravity + Review-Driven Development（A=後端 / B=前端）

## Milestone: W1–W2 Foundation（基礎架構 + 同步框架 + Auth）

**Epic 1: Monorepo 初始化與 Contract-First 定義**
- [x] **Agent A-0（新增）**：產出 Sync API Spec Artifact（Contract-First） #1
  - 產生 `docs/api-contract-sync-v1.6.yaml`（OpenAPI 格式）
  - 定義所有 operation 結構、created_at 排序規則、錯誤碼與 server_state 格式
  - 前後端 Schema 必須以此檔案為唯一真相來源
- [x] Agent A-1：初始化 Fastify 專案 + Drizzle Schema（全 8 表） #2
- [x] Agent B-1：Flutter 專案 + Drift Schema + build_runner #3

**Epic 2: Auth 與 Sync 骨架**
- [x] Agent A-2：Auth JWT 中間件 + 角色權限矩陣 
- [x] Agent A-3：POST /api/v1/sync/push 骨架 + 錯誤碼回傳 
- [x] Agent B-2：SyncProvider 骨架（Riverpod）+ 離線佇列 

**W1 Gate 檢查清單**（全部通過才可關閉 Milestone）
- [x] `docs/api-contract-sync-v1.6.yaml` 已產出且前後端 Schema 一致
- [x] docker ps + Drizzle Studio 可連線
- [x] flutter doctor -v 全綠
- [x] operations 依 created_at 升序 + 單批上限 50 筆

## Milestone: W3–W4 CRUD
- [x] Agent A：客戶 / 產品 REST API（含軟刪除 + 權限） #4
- [x] **Agent B（修正強化）**：客戶 / 產品列表 UI + 離線新增 + 軟刪除 #5
  - **強制規則**：UI 刪除一律使用 `deleted_at` 標記（不得 Hard Delete）
  - 同步時必須正確傳送 deleted_at 更新（LWW 判斷依據）
- [x] Agent B：LWW 衝突解決實作（updated_at 比較） #6

## Milestone: W5 CRM
- [x] Agent A：報價 API + 報價轉訂單（First-to-Sync wins） #7
- [x] Agent B：報價單 UI（稅額切換 + decimal） #8

## Milestone: W6–W8 SCM（最核心）
**Epic: DELTA_UPDATE 庫存邏輯**
- [x] Agent A：實作 DELTA_UPDATE 四種 type（reserve/cancel/out/in） #9
- [x] Agent A：INSUFFICIENT_STOCK 409 + Fail-to-Pull 機制 #10
- [x] **Agent A/B 共同（新增）**：併發衝突模擬測試（Race Condition） #11
  - 模擬兩台裝置同時對同一商品執行 out/reserve
  - 驗證 First-to-Sync wins + 409 Conflict → 前端強制 Pull 流程
  - 確保 `quantity_on_hand >= 0 && quantity_reserved <= quantity_on_hand`

**Epic: 訂單與出貨流程**
- [x] Agent B：確認訂單 → reserve UI 流程（不自動 reserve） #12
- [x] Agent B：出貨 UI（type: out） #13
- [x] **Agent Antigravity**：全域系統審計、合規性檢查與效能優化 
  - 修復 `GET /pull` 明細缺失漏洞
  - 優化 `SyncProvider.pullData()` 批次交易效能
  - 修正 Drift Schema 相容性與全域代碼清理（Fix 36+ analysis issues）
- [ ] 共同：W6 末 離線建單 → 同步 → 庫存更新走路測試 #14

## Milestone: W9 Dashboard & Data Import
- [ ] 共同：簡易儀表板（待出貨、低庫存、本月報價） #15
- [ ] **共同（新增）**：CSV/Excel Import Tool（初始資料匯入） #16
  - 支援產品、客戶、庫存初始匯入（含 inbound DELTA_UPDATE type:in）
  - 驗證庫存初始化正確性
- [ ] 共同：processed_operations 30 天清理 + 軟刪除清理 #17

## Milestone: W10 Polish & Test
- [ ] 全域 Bug Fix + 整合測試 #18
- [ ] 同步成功率 >90% / 庫存準確率 >95%
- [ ] 最終驗收清單（同步協定核心項目）

**所有 Issue 關閉前必須** 使用 `sync_logic_check` Template 自證符合同步協定 v1.6。
