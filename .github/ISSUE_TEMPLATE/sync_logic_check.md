---
name: Sync Logic Check
about: Agent 關閉 Issue 前必須自證符合同步協定 v1.6
title: '[Sync Check] '
labels: sync, agent-task
assignees: ''

---

**本 Issue 對應同步協定 v1.6 第幾條？**  
（請明確填入，例如：4. 庫存 DELTA_UPDATE、5. API 契約、6. 錯誤代碼表、7. 特殊業務規則）

**自證檢查清單**（Agent 必須全部勾選並附證明）：
- [ ] operations 已依 `created_at` 升序排列（跨批次一致）
- [ ] 單批 operations ≤ 50 筆
- [ ] deleted_at 使用 LWW（非 Hard Delete，本地僅標記 deleted_at）
- [ ] INSUFFICIENT_STOCK (409) → 前端強制 Pull（非 Force Overwrite）
- [ ] FORBIDDEN_OPERATION / PERMISSION_DENIED / VALIDATION_ERROR → 使用 server_state Force Overwrite
- [ ] quantity_on_hand >= 0 且 quantity_reserved <= quantity_on_hand（所有 DELTA_UPDATE 後）
- [ ] 測試證明（Fiddler 截圖 / Artifact / Vitest 測試結果）已上傳
- [ ] 已通過人工 Review（Antigravity Artifact 注解已整合）

**相關 Artifact 連結**：
（請貼上 Antigravity 產出的計畫、diff、測試截圖）

**開發者審核意見**：
