# NJ_Stream_ERP Issue #6 執行策略 (Sync Pull & Auth UI)

此計畫已經根據 `docs/**/*.md` 與 `api-contract-sync-v1.6.yaml` 作為**最高指導原則**重新檢視。以下是嚴格遵守合約的執行策略：

## User Review Required

> [!WARNING]
> **離線負數 ID 對應衝突 (雙胞胎問題) 在當前合約下的解法**
> 根據 `NJ_Stream_ERP MVP 同步協定規格 v1.6.md` 與 `api-contract`：
> - 伺服器端收到 `push` 的建立操作，是產生自動遞增的 `id`（見 `sync.service.ts`）完全忽略本地傳送的 `-1`。
> - 合約 `succeeded` 只會回傳 UUID 的 `operationId` 陣列，並沒有回傳伺服器配發的 `id`。
> - 後端沒有支援離線 `client_id` 機制。
>
> 📌 **本階段 (W2) 遵照合約的解法：**
> 由於我們**不能**隨意違反合約去修改 push 端點回傳值，Pull 機制必須能處理已經建立成功的 `-1` 實體。
> 發動 `GET /api/v1/sync/pull` 取回增量資料前（或剛收到 Push success 後），前端將直接清除本地**所有未在 Pending 操作中關聯的負數 ID**，並無條件套用 Pull 下來的全量 / 增量資料，這樣便能靠伺服器狀態「覆蓋」過渡期的臨時資料，消滅雙胞胎問題而不影響現有合約結構。請確認是否同意以此作為防護機制？

> [!IMPORTANT]
> **API Contract v1.6 的修訂**
> 在 `api-contract-sync-v1.6.yaml` 中，記載了 `GET /api/v1/sync/pull` 目前狀態是 `TBD — W6 Sprint Planning 前確認回傳結構`。
> 我會在本次任務中完善此 Schema 的實作定義（各列表加上 `since` 過濾）。

## Proposed Changes

---

### Phase 1: API Contract 完善 (Agent A 視角)
#### [MODIFY] [api-contract-sync-v1.6.yaml](file:///c:/Users/archi/OneDrive/Desktop/NJ_Stream_ERP/docs/api-contract-sync-v1.6.yaml)
- 補齊 `GET /api/v1/sync/pull` 端點。
- 確立回傳結構。例如：
  ```json
  {
    "customers": [...],
    "products": [...],
    "quotations": [...],
    "salesOrders": [...],
    "inventoryDeltas": [...]
  }
  ```

### Phase 2: 後端 Pull 端點開發 (Agent A 視角)
#### [NEW] [pull.route.ts](file:///c:/Users/archi/OneDrive/Desktop/NJ_Stream_ERP/packages/backend/src/routes/sync/pull.route.ts) （或於 sync.route 中實作）
- 建立 `GET /api/v1/sync/pull` 端點，讀取 `since` 參數。
- 撈出 `customers`、`products` 等資料表中 `updated_at > since` 的紀錄，並做權限過濾後回傳。

### Phase 3: 前端 SyncProvider 修復與 Pull 機制 (Agent B 視角)
#### [MODIFY] [sync_provider.dart](file:///c:/Users/archi/OneDrive/Desktop/NJ_Stream_ERP/packages/frontend/lib/providers/sync_provider.dart)
- **修正 Push Req/Res 合約不匹配**：將舊代碼 `entity` / `operation` 修改為 `entityType` / `operationType`，並依照 `{succeeded: [], failed: []}` 格式正確解析後端回應（目前是錯讀了舊版 `results` 陣列，這在稍早 `Push` 結果中無法發揮作用）。
- **Pull 增量狀態**：增加 `flutter_secure_storage` 紀錄 `last_sync_at` 機制。
- **實作 `pullData()`**：定時或在 Push 成功/遇到庫存異常與 Force Overwrite 時觸發拉取。

#### [MODIFY] [app_database.dart 等諸多 Dao](file:///c:/Users/archi/OneDrive/Desktop/NJ_Stream_ERP/packages/frontend/lib/database/database.dart)
- 實踐 **LWW (Last-Write-Wins)**：`upsertCustomerFromServer(serverState)` 比對 `server.updatedAt` 與 `local.updatedAt`。如果伺服器資料較新，則覆蓋至 Drift。
- **清除滯留離線資料**：Pull 前移除本地多餘且不在 pending 狀態的 `id < 0` 的實體。

### Phase 4: Auth UI 實作
#### [MODIFY] [login_screen.dart] (新建於 features/auth/)
- 替換 `LoginPlaceholderScreen`，實際呼叫 `POST /api/v1/auth/login`。
- 接上 `SyncProvider` 的狀態刷新 `HomeScreen`。

## Open Questions
- 您傾向將 Pull 端點放在一個獨立的檔案（例如 `pull.route.ts` 並且掛載回 `app`），還是直接把 GET 規則寫進已有的 `sync.route.ts`？（目前 `sync.route` 只有 150 行以內，合在一起較為緊湊）。

## Verification Plan
1. `npm run check` 確認 Backend Zod / 表單定義無誤。
2. 啟動 Fastify 後端。呼叫 `GET /api/v1/sync/pull` 確認型別與日期範圍邏輯正確。
3. `dart run build_runner build` 生成 DAO 更新，測試 Flutter 端送出 `Push` 後接上 `Pull` 清倉與更新，確保 UI 的狀態不再駐留負數 ID。
