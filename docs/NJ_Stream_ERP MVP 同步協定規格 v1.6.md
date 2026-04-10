# NJ_Stream_ERP MVP 同步協定規格 v1.6
**最終版**（2026 年 3 月）

**文件目的**：本文件為離線同步機制的最高指導原則（工程憲法）。

## 1. 核心憲法
- 本地 Drift 為單一真相來源（SSOT）
- 衝突解決：非庫存用 LWW，庫存用 Delta Update + Fail-to-Pull
- 關鍵業務操作視為原子操作

## 4. 庫存 DELTA_UPDATE 處理規則

| type      | 說明               | quantity_on_hand 變化 | quantity_reserved 變化 | 使用情境               |
|-----------|--------------------|-----------------------|------------------------|------------------------|
| in        | 入庫               | + amount              | 不變                   | 採購入庫               |
| reserve   | 確認訂單鎖定       | 不變                  | + amount               | 業務確認訂單           |
| cancel    | 取消訂單（釋放）   | 不變                  | - amount               | 取消已確認訂單         |
| out       | 出貨               | - amount              | - amount               | 實際出貨               |

**約束條件**：`quantity_on_hand >= 0` 且 `quantity_reserved <= quantity_on_hand`

## 5. API 契約
- **POST /api/v1/sync/push**
  - `operations` 陣列上限 50 筆
  - **分批推送順序保證**：所有 operations 必須依照 `created_at` 升序排列，跨批次亦需保持一致。
  - **回傳值強化**：失敗的 operation 必須包含 `server_state` 欄位（僅該 entity 本身的欄位，不含關聯資料），供前端執行 Force Overwrite。

**Force Overwrite 處理原則**：
前端收到 `FORBIDDEN_OPERATION`、`PERMISSION_DENIED` 或 `VALIDATION_ERROR` 時，直接使用 `server_state` 中的資料覆蓋本地對應 entity，不進行重試。

## 6. API 錯誤代碼表

| 錯誤代碼              | HTTP 狀態碼 | 前端處理策略                          | 備註 |
|-----------------------|-------------|---------------------------------------|------|
| INSUFFICIENT_STOCK    | 409         | 強制 Pull                             | 庫存變動 |
| FORBIDDEN_OPERATION   | 403         | 使用 server_state 進行 Force Overwrite | 權限不足 |
| PERMISSION_DENIED     | 403         | 使用 server_state 進行 Force Overwrite | 角色無權限 |
| VALIDATION_ERROR      | 400         | 使用 server_state 進行 Force Overwrite | 驗證失敗 |
| DATA_CONFLICT         | 409         | 標記 failed，人工介入                 | 嚴重衝突 |

## 7. 特殊業務規則
- **報價轉訂單時機**（保守設計）：
  - 報價轉訂單僅建立 `sales_orders` 記錄（CREATE），**不自動觸發 reserve**。
  - 業務手動「確認訂單」後才執行 `DELTA_UPDATE type: reserve`。
- **報價轉訂單併發控制**：First-to-Sync wins，若已轉換則忽略重複請求。

## 8. Addendum
- processed_operations 每週清理 30 天以上記錄
- 軟刪除：App 啟動時清理 30 天以上記錄
- 稅額顯示：前端離線顯示「預估稅額」，同步後若後端覆蓋則顯示「已調整」提示

**W1 凍結確認**：v1.6 已為最終版，所有技術細節與 PRD 保持一致，可直接用於開發。