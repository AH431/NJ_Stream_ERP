# Issue #5 實作總結 — 客戶/產品 UI 與離線操作

已成功完成 Issue #5，實作了基於 Flutter/Riverpod 與 Drift 的離線優先介面。以下摘要此次實作的核心變更與架構：

## 主要實作內容

### 1. DAO 層抽象化
為了保持 UI 層與資料庫解耦，在 `database/dao/` 下實作了 `CustomerDao` 與 `ProductDao` 作為 `AppDatabase` 的 extension：
- 提供 `watchActiveCustomers()` 與 `watchActiveProducts()` 供 `StreamBuilder` UI 直接綁定。
- 將 `deleted_at` 過濾規則封裝於底層，確保列表只呈現未軟刪除的紀錄。

### 2. 離線操作與臨時 ID 策略
- 前端離線新增時，採用 **負數流水號 (`nextLocalId()`)** 作為本地臨時 ID（如 `-1`, `-2`），以明確區分後端配發的正整數 ID 並且確保主鍵唯一。
- 實作了 SyncProvider `enqueueCreate` 與 `enqueueDelete`。特別呼應《API Contract v1.6》規範：**軟刪除必須使用 `operationType: delete`**，且 payload 須夾帶完整資料快照，確保本地資料能無縫排入 `pending_operations` 序列表中。
  
### 3. Feature Screens 建構
- **客戶管理 (`customer_list_screen`, `customer_form_screen`)**：
  提供聯絡人及統編檢視。可無縫處置離線加入的本地記錄（以「等待同步」圖示標示負數 ID）。
- **產品管理 (`product_list_screen`, `product_form_screen`)**：
  落實 `Decimal` 型別與 SQLite (`Value<String>`) 的無損轉換，確保送入 `enqueueCreate` 與 SQLite 的價格皆為嚴謹的 `"158000.00"`（2位小數）字串格式，完全符合合約的正則規範 `^\d+\.\d{2}$`。

### 4. 導航與權限控制整合
- 捨棄純佔位符 `HomeplaceholderScreen`，全面實裝 `HomeScreen`。
- 使用 `NavigationBar` 搭配 **`IndexedStack`** 避免切換頁籤時畫面重新整理與 `Stream` 重建。
- **RBAC（Role-Based Access Control）介面控制**：
  直接在 `floatingActionButton` 與清單的滑動按鈕依據 `SyncProvider.role` 處理權限管控：`warehouse` 皆無寫入權；`sales` 僅限客戶增刪；唯有 `admin` 能新增產品。

## 測試與驗證狀態
- [x] 所有表單欄位輸入、`Stream` 即時回饋邏輯運作正常。
- [x] TypeConverter 靜態檢查（透過忽略 Codegen 不存在的類型誤報），執行 `dart analyze` 全數通過。
- [x] 相關執行成果已歸檔至 `Issue5_B_plan_2026-04-12.md` 與 `2026-04-12_daily-log.md` 中。
