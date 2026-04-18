# NJ_Stream_ERP MVP PRD v0.8
**羽量級行動優先 ERP**  
**版本**：MVP v0.8（2026 年 3 月最終版）

## 1. 產品概述
- **產品名稱**：NJ_Stream_ERP（羽量級行動優先 ERP）
- **目標用戶**：台灣中小企業（貿易、批發、零售、輕製造），5-50 人規模
- **核心價值主張**：行動優先、極致輕量化、聚焦最核心的進銷存 + CRM 流程
- **技術方向**：Flutter + Drift（前端） / Node.js + Fastify + Drizzle ORM（後端）

## 2. 業務目標與成功指標
- 庫存準確率（含預留量）> 95%
- 離線操作後同步成功率 > 90%
- 核心業務閉環走通：客戶 → 報價 → 訂單 → 確認訂單 → 出貨

## 3. 使用者角色與權限

### 角色權限矩陣（最終版）

| 功能                 | Sales (業務) | Warehouse (倉管) | Admin    |
|----------------------|--------------|------------------|----------|
| 客戶、商機、報價     | 讀寫         | 唯讀             | 讀寫     |
| 報價轉訂單           | 可執行       | 無               | 可執行   |
| 確認 / 取消訂單      | 可執行       | 唯讀             | 可執行   |
| 入出庫操作           | 無           | 讀寫             | 讀寫     |
| 庫存查詢             | 唯讀         | 讀寫             | 讀寫     |
| 產品管理             | 唯讀         | 唯讀             | 讀寫     |
| 使用者管理           | 無           | 無               | 讀寫     |
| PDF 匯出 / Email 寄送 | 可執行      | 無               | 可執行   |

**說明**：
- Sales 可建立報價並轉訂單，但不可執行實際入出庫。
- Warehouse 專注實體庫存操作，對訂單僅有唯讀權限（可查看訂單是否已確認，以便執行出貨）。
- Admin 擁有最高權限。

## 4. 核心功能需求

### 4.1 CRM 模組
- 客戶管理、商機管理
- **報價管理**：
  - 建立報價單（未稅 / 含稅切換，前端計算 5% 稅額並標註「預估稅額」）
  - **報價轉訂單流程**：
    - 轉換成功後，報價狀態變更為 **"converted"** 並鎖定。
    - 轉訂單僅建立 `sales_orders` 記錄（CREATE），**不自動觸發 reserve**。
    - 業務需手動「確認訂單」後才執行 `DELTA_UPDATE type: reserve`。
    - 併發控制：First-to-Sync wins，若已轉換則忽略重複請求。

### 4.2 SCM 模組
- 產品管理
- **庫存管理**（MVP 階段僅支援單一預設倉庫）：
  - `warehouse_id` 欄位保留但 UI 暫時隱藏，所有操作預設使用單一倉庫。
  - **庫存鎖定生命週期**：
    - reserve（確認訂單）：+ reserved
    - cancel（取消訂單）：- reserved
    - out（出貨）：同時 - on_hand 與 - reserved
  - 可用庫存計算公式：`Available = OnHand - Reserved`

- 銷售訂單與出貨、採購與入庫

### 4.3 共用基礎功能
- **簡易儀表板**（已凍結）：
  - 待出貨訂單數
  - 低庫存產品列表（依各產品 `min_stock_level`，預設 0）
  - 本月報價總額（含稅）
- **離線同步機制**：詳見獨立文件《NJ_Stream_ERP MVP 同步協定規格 v1.6》
- **稅額顯示**：離線時顯示「預估稅額」，同步後若後端覆蓋則顯示「已調整」提示。
- **文件輸出與 Email 通知**：
  - 報價單 / 訂單匯出 PDF（後端以 `pdfkit` 產生，前端透過 API 下載）
  - 一鍵 email 寄送 PDF 給客戶（後端以 `nodemailer` + SMTP 寄送，收件地址取自 customers 表）
  - 客戶月結對帳單：依年月查詢該客戶所有訂單，合併產生一份 PDF 並可 email 寄送
  - **後端新增 API**：
    - `GET  /quotations/:id/pdf`
    - `GET  /sales-orders/:id/pdf`
    - `GET  /customers/:id/statement?year=&month=`
    - `POST /quotations/:id/send-email`
    - `POST /sales-orders/:id/send-email`
    - `POST /customers/:id/send-statement`
  - **權限**：Sales / Admin 可執行；Warehouse 無此功能
  - **SMTP 設定**：透過後端 `.env`（`SMTP_HOST` / `SMTP_USER` / `SMTP_PASS`）

## 5. 非功能性需求
- 離線同步機制詳見《NJ_Stream_ERP MVP 同步協定規格 v1.6》
- 權限衝突處理：後端拒絕時回傳 `server_state`，前端執行 Force Overwrite（僅覆蓋該 entity 本身欄位）
- App 安裝檔 < 300MB，後端極輕
- 稅務計算：前端使用 `decimal` 套件

## 6. 技術架構概要
- 前端：Flutter + Drift + Riverpod
- 後端：Fastify + Drizzle ORM + PostgreSQL
- 同步機制：詳見同步協定 v1.6

## 7. 開發階段與 10 週排程
- W1–W2：基礎架構 + 同步框架 + Auth + 權限
- W3–W4：客戶 / 產品 CRUD
- W5：CRM（報價 + 報價轉訂單）
- W6–W8：SCM（訂單、庫存預留、出貨）
- W6 末：離線建單 → 同步 → 庫存更新走路測試
- W9：簡易儀表板 + 整合
- W10：測試與緩衝（W9 起停止新增功能）

## 8. 分工建議
- 人員 A（後端）：Fastify API、Drizzle Schema、同步邏輯
- 人員 B（前端）：Flutter + Drift、SyncProvider、UI

## 9. 不在 MVP 範圍
- 完整財務會計、製造、HR 模組
- 進階 BI 圖表、附件 S3、推播通知、電子發票等
- 多倉庫完整功能（MVP 僅單一預設倉庫）
- 批次/序號追蹤、深度 LINE 整合

**原則**：嚴格 80/20，只做最核心閉環。