#!/bin/bash
# NJ_Stream_ERP MVP - GitHub CLI Setup Script (v1.2)
# 功能：建立 Labels + Milestones + Issues
# 使用前請先在 repo 根目錄執行，並確保 gh 已登入 (gh auth login)

set +e

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "🚀 開始在 $REPO 設定 GitHub Labels、Milestones 與 Issues..."

# ====================== 1. 建立常用 Labels ======================
echo "🏷️  建立常用 Labels..."

gh label create backend \
  --description "後端相關任務 (Fastify + Drizzle)" \
  --color "0E8A16" || true

gh label create frontend \
  --description "前端相關任務 (Flutter + Drift + Riverpod)" \
  --color "006B75" || true

gh label create sync \
  --description "離線同步邏輯相關" \
  --color "5319E7" || true

gh label create "agent-task" \
  --description "Antigravity Agent 負責的任務" \
  --color "D93F0B" || true

gh label create "high-priority" \
  --description "高優先級任務（影響核心流程）" \
  --color "B60205" || true

gh label create "race-condition" \
  --description "併發衝突 / Race Condition 測試" \
  --color "F9A825" || true

gh label create "data-import" \
  --description "CSV/Excel 資料匯入相關" \
  --color "0E8A16" || true

gh label create "contract-first" \
  --description "Contract-First API Spec 相關" \
  --color "C2E0C6" || true

gh label create "soft-delete" \
  --description "軟刪除 (deleted_at) 相關" \
  --color "FBCA04" || true

gh label create "delta-update" \
  --description "庫存 DELTA_UPDATE 四種 type" \
  --color "5319E7" || true

gh label create "dashboard" \
  --description "儀表板相關功能" \
  --color "1D76DB" || true

echo "✅ Labels 建立完成！"

# ====================== 2. 建立 Milestones ======================
echo "📅 建立 6 個 Milestones..."

create_milestone() {
  local title="$1"
  local description="$2"
  local due="$3"
  gh api repos/$REPO/milestones \
    --method POST \
    --field title="$title" \
    --field description="$description" \
    --field due_on="${due}T00:00:00Z" \
    --silent || true
}

create_milestone "W1–W2 Foundation" "基礎架構 + 同步框架 + Auth + Contract-First（W1 Gate）" "2026-04-04"
create_milestone "W3–W4 CRUD" "客戶 / 產品 CRUD + 軟刪除 + LWW 衝突解決" "2026-04-18"
create_milestone "W5 CRM" "報價管理 + 報價轉訂單" "2026-04-25"
create_milestone "W6–W8 SCM" "訂單確認、出貨、DELTA_UPDATE 庫存邏輯 + Race Condition 測試" "2026-05-16"
create_milestone "W9 Dashboard & Import" "儀表板 + CSV/Excel Import Tool + 清理機制" "2026-05-23"
create_milestone "W10 Polish & Test" "最終 Bug Fix + 整合測試 + 驗收（同步成功率 >90%, 庫存準確率 >95%）" "2026-05-30"

echo "✅ Milestones 建立完成！"

# ====================== 3. 建立 Issues ======================
echo "📋 建立 Issues 並關聯 Milestone..."

# W1–W2
gh issue create --title "Agent A-0: 產出 Sync API Spec Artifact (Contract-First)" \
  --body "產生 docs/api-contract-sync-v1.6.yaml 作為前後端 Schema 單一真相來源。\n\n參考：開發計畫書 3.2 與同步協定 v1.6" \
  --milestone "W1–W2 Foundation" \
  --label "contract-first,agent-task,high-priority,backend" || true

gh issue create --title "Agent A-1: 初始化 Fastify 專案 + Drizzle Schema (全 8 表)" \
  --body "包含 processed_operations 30 天清理機制。\n\nW1 Gate 驗收：Drizzle Studio 可視化所有表" \
  --milestone "W1–W2 Foundation" \
  --label "backend,agent-task" || true

gh issue create --title "Agent B-1: Flutter 專案 + Drift Schema + build_runner" \
  --body "flutter pub run build_runner watch 無錯誤" \
  --milestone "W1–W2 Foundation" \
  --label "frontend,agent-task" || true

# W3–W4
gh issue create --title "Agent A: 客戶 / 產品 REST API（含軟刪除 + 權限）" \
  --body "Sales / Warehouse / Admin 角色權限正確" \
  --milestone "W3–W4 CRUD" \
  --label "backend" || true

gh issue create --title "Agent B: 客戶 / 產品列表 UI + 離線新增 + 軟刪除" \
  --body "**重要**：刪除一律使用 deleted_at 標記（不得 Hard Delete），符合 LWW 原則" \
  --milestone "W3–W4 CRUD" \
  --label "frontend,soft-delete" || true

gh issue create --title "Agent B: LWW 衝突解決實作" \
  --body "以 updated_at 較新者為準，Fiddler 驗證" \
  --milestone "W3–W4 CRUD" \
  --label "frontend,sync" || true

# W5
gh issue create --title "Agent A: 報價 API + 報價轉訂單（First-to-Sync wins）" \
  --body "轉換後鎖定，不自動 reserve" \
  --milestone "W5 CRM" \
  --label "backend" || true

gh issue create --title "Agent B: 報價單 UI（稅額切換 + decimal）" \
  --body "離線顯示預估稅額，同步後顯示「已調整」提示" \
  --milestone "W5 CRM" \
  --label "frontend" || true

# W6–W8
gh issue create --title "Agent A: 實作 DELTA_UPDATE 四種 type（reserve/cancel/out/in）" \
  --body "在 transaction 中確保 quantity_on_hand >= 0 且 quantity_reserved <= quantity_on_hand" \
  --milestone "W6–W8 SCM" \
  --label "backend,delta-update" || true

gh issue create --title "Agent A: INSUFFICIENT_STOCK 409 + Fail-to-Pull 機制" \
  --body "庫存不足時回 409，前端強制 Pull" \
  --milestone "W6–W8 SCM" \
  --label "backend,sync" || true

gh issue create --title "共同: 併發衝突模擬測試（Race Condition）" \
  --body "模擬兩台裝置同時操作同一商品，驗證 First-to-Sync wins + Force Pull" \
  --milestone "W6–W8 SCM" \
  --label "race-condition,high-priority" || true

gh issue create --title "Agent B: 確認訂單 → reserve UI 流程" \
  --body "不自動 reserve，業務手動確認後才執行" \
  --milestone "W6–W8 SCM" \
  --label "frontend" || true

gh issue create --title "Agent B: 出貨 UI（type: out）" \
  --body "同時扣 quantity_on_hand 與 quantity_reserved" \
  --milestone "W6–W8 SCM" \
  --label "frontend" || true

gh issue create --title "共同: W6 末 離線建單 → 同步 → 庫存更新走路測試" \
  --body "端到端驗證：客戶 → 報價 → 訂單 → 確認 → 出貨 → 庫存正確" \
  --milestone "W6–W8 SCM" \
  --label "high-priority" || true

# W9
gh issue create --title "共同: 簡易儀表板（待出貨、低庫存、本月報價）" \
  --body "低庫存依 min_stock_level 計算" \
  --milestone "W9 Dashboard & Import" \
  --label "dashboard" || true

gh issue create --title "共同: CSV/Excel Import Tool（初始資料匯入）" \
  --body "支援產品、客戶、庫存初始匯入（含 type:in）" \
  --milestone "W9 Dashboard & Import" \
  --label "data-import" || true

gh issue create --title "共同: processed_operations 30 天清理 + 軟刪除清理" \
  --body "排程任務，不影響正在同步的 operations" \
  --milestone "W9 Dashboard & Import" \
  --label "backend" || true

# W10
gh issue create --title "W10: 全域 Bug Fix + 整合測試 + 最終驗收" \
  --body "同步成功率 >90%；庫存準確率 >95%\n\n所有 Issue 關閉前請使用 sync_logic_check template 自證" \
  --milestone "W10 Polish & Test" \
  --label "high-priority" || true

echo "🎉 所有 Labels、Milestones 與 Issues 建立完成！"
echo ""
echo "下一步建議："
echo "1. 執行：gh issue list --milestone \"W1–W2 Foundation\"  查看 W1 任務"
echo "2. 開啟 GitHub Projects (Kanban) 並把 Issues 拖入對應欄位"
echo "3. 開始讓 Antigravity Agent 處理第 1 個 Issue（Contract-First）"
echo "4. 記得在關閉 Issue 前使用 sync_logic_check template"
