# Issue #6 實作總結 — Sync Pull, LWW 與 Auth 整合

本次任務我們嚴格按照 `docs` 中的 MVP 合約規範，且在不異動合約底層理念下，實作了 Issue #6 所要求的四大核心功能板塊。

## 1. Sync Pull 規格與端點 (Backend)
- 補齊了本來在設計文件標記為 `TBD` 的 `/api/v1/sync/pull` 端點。
- 更新 `api-contract-sync-v1.6.yaml`：加入了詳細的回傳陣列結構（如 `customers`, `products`），並支援以增量 `since` 日期作為引數。
- 在後端路由正式加了 `GET /pull`：可即時針對最新時間抓出變更資料給前端。

## 2. SyncProvider 推送合約對齊 (Frontend)
- 修正 `_pushBatch` 所夾帶的 JSON 取名：原本舊版的 `entity` 已更正為 `entityType`，`operation` 更正為 `operationType`，完成與新版 Zod Schema 的 100% 對接。
- 修正 Response 處理邏輯：已根據 `succeeded` 陣列以及 `failed` 的 `operationId` 物件進行對比（包含解讀 `error_code`）。

## 3. Pull 機制與 LWW 衝突解決 (Frontend)
- 實作了 `SyncProvider.pullData()`。
- **清除滯留負數的防護機制**：我們透過比對「尚在等待上傳的 queue (Pending)」中的關聯 IDs，將多出來的負數 `id=-1` 孤兒紀錄刪除，以徹底避開從 Server 拉回實際 ID (`101`) 時產生雙胞胎的問題。這個解法順暢且無需干預 `POST /push` 的預設回傳協定。
- 各大 DAO（如 `CustomerDao`）加入了 LWW 本地衝突覆寫策略的 `upsert...FromServer`：只有當後端傳來的 `updatedAt` 比起本地還新的時候，才會執行資料庫覆蓋。

## 4. Auth UI 實裝
- 移除原本掛在首頁的佔位符：`LoginPlaceholderScreen`。
- 獨立建立了 `lib/features/auth/login_screen.dart`，加入標準的帳密頁面，包含狀態處理（UI 的 Loading 指示器）、驗證檢整，並銜接了 SyncProvider 中的 `login()` API 到 `flutter_secure_storage` 中。

## 測試與驗證狀態
- [x] 所有 API 合約已被遵守與更新。
- [x] Backend Tsc Build 通過。
- [x] Frontend Dart Analyzer 一切通過（僅剩下 Drift Codegen 無法辨識的已知靜態小誤報）。
