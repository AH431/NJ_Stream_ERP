# 專案合規性、穩定性與效能優化審計修復計畫

根據對專案目前的檢驗，整體架構（Sync Protocol v1.6, PRD v0.8）執行良好，但仍存在部分邏輯缺失、代碼冗餘與效能優化空間。本計畫旨在修復這些問題以達成「效能最大化與穩定合規」的目標。

## 審計發現與修復重點

### 1. 後端同步邏輯補完 (Compliance & Stability)
- **問題**：`GET /pull` 接口目前未回傳 `quotations` 與 `sales_orders` 的明細 (`items`)。這會導致客戶端在進行全量同步或 Fail-to-Pull 時遺失報價/訂單內容。
- **方案**：修改 `sync.route.ts`，在 `pull` 邏輯中透過 Join 或獨立查詢補齊明細資料。

### 2. 前端代碼品質與穩定性 (Stability)
- **問題**：`dart analyze` 檢出 36 個問題，包含大量未使用的 Import、棄用的 API (`withOpacity`) 以及潛在的類型警告。
- **方案**：執行全域代碼清理，移除冗餘 Import 並更新棄用 API 為 `withValues()`。

### 3. 前端同步效能優化 (Performance)
- **問題**：`SyncProvider.pullData()` 在處理大批量數據（如 100+ 客戶或產品）時，目前的實作是逐筆等待 Upsert，這會頻繁觸發資料庫寫入锁與 UI 通知。
- **方案**：
  - 使用 Drift 的 `batch` 或 `transaction` 包裹 Pull 過程中的所有資料庫操作，減少寫入次數。
  - 確保只在整批更新完成後觸發一次 `notifyListeners()`。

### 4. 任務清單一致性 (Rationalization)
- **問題**：`TASKS.md` 與 `LOG` 中的 Issue 編號存在不一致。
- **方案**：統一編號，確保專案管理文件的準確性。

## Proposed Changes

### [Backend] SCM & Sync

#### [MODIFY] [sync.route.ts](file:///c:/Projects/NJ_Stream_ERP/packages/backend/src/routes/sync.route.ts)
- 補齊 `GET /pull` 中 `quotations` 與 `salesOrders` 的明細查詢。
- 優化查詢效率，避免 N+1 問題。

---

### [Frontend] Database & Providers

#### [MODIFY] [sync_provider.dart](file:///c:/Projects/NJ_Stream_ERP/packages/frontend/lib/providers/sync_provider.dart)
- 修改 `pullData` 以使用 `_db.batch` 執行所有 Upsert 操作。
- 修正 `dart analyze` 檢出的警告與提示。

#### [MODIFY] 各 Feature Screen 與 Companion 檔案
- 移除 `unused_import`。

---

## 驗證計畫

### 自動化測試
- 運行 `npm run build` 確保編譯通過。
- 運行 `dart analyze` 確保 issue 數歸零。

### 手動驗證
- 透過 `pullData()` 驗證報價單明細是否正確從伺服器拉取並在本地正確顯示。
- 監控同步時的記憶體與 CPU 佔用，驗證效能優化效果。
