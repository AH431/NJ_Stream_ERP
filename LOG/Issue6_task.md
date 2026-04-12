# Issue #6 Task List — Sync Pull 機制與 Auth UI

## Phase 1: API Contract
- [x] 修改 `api-contract-sync-v1.6.yaml` 加入 `GET /api/v1/sync/pull` 端點。

## Phase 2: 後端 Pull 實作
- [x] 修改 `backend/src/routes/sync.route.ts` 加入 `OPTIONS /pull` 與 `GET /pull` 端點。
- [x] 實作讀取所有 `updated_at >= since` 且符合權限的資料。

## Phase 3: 前端 DAO 與 LWW
- [x] `CustomerDao`: 加入 `upsertCustomerFromServer(serverState)` 與清空 `-1` 方法。
- [x] `ProductDao`: 加入 `upsertProductFromServer(serverState)` 與清空 `-1` 方法。

## Phase 4: SyncProvider
- [x] 修改 `_pushBatch` 傳送 payload 的 key 為 `entityType`, `operationType` 等。
- [x] 修改 `_pushBatch` 的結果解析為 `{ succeeded, failed }`。
- [x] 實作 `pullData()` 方法串接後端 `/pull` 並呼叫各個 DAO，儲存 `last_sync_at`。

## Phase 5: Auth UI
- [x] 實作 `features/auth/login_screen.dart`。
- [x] 取代 `main.dart` 裡的 `LoginPlaceholderScreen`。

## Phase 6: 驗證
- [x] 確保 `dart analyze` 通過。
- [x] 確保後端 `npm run build` 通過。
