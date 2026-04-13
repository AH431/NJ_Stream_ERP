# Issue #14 Task List — W6 末 端到端走路測試

**Milestone**：W6–W8 SCM  
**Agent**：共同（A + B）  
**前置 Issue**：#9–#13 全部完成 ✅

---

## 範疇說明

| 驗收目標 | 說明 |
|---------|------|
| 業務閉環 | 客戶 → 報價 → 訂單 → 確認 → 預留 → 出貨 完整走通 |
| 離線建單 | 在無網路狀態完成前三步，同步後資料一致 |
| 庫存數字 | Push/Pull 後 `onHand` / `reserved` 符合預期公式 |
| 新 UI 流程 | Issue #12（ReserveInventoryDialog）+ #13（ShipOrderDialog）實際驗收 |
| 角色權限 | sales 建單確認預留 / warehouse 執行出貨 |

---

## 庫存數字預期公式

```
初始：       onHand = H,  reserved = 0
reserve N：  onHand = H,  reserved = N
out N：      onHand = H-N, reserved = 0   ← 最終期望狀態
```

---

## Phase 0：環境準備

### 0-1. 後端啟動確認

```bash
# packages/backend/
npm run dev          # Fastify 監聽 :3000
# 確認輸出：Server listening at http://0.0.0.0:3000
```

### 0-2. 取得 JWT（admin_test）

```bash
TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin_test","password":"P@ssw0rd!"}' \
  | jq -r '.token')
echo $TOKEN   # 非空即可
```

### 0-3. 確認測試商品 + 庫存存在

```bash
# 取得所有 inventory_items（since 遠古，含全部資料）
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/sync/pull?entityTypes=product,inventory_delta&since=2020-01-01T00:00:00Z" \
  | jq '{products: [.products[]|{id,name,sku}], inventory: [.inventoryItems[]|{id,productId,onHand:.quantityOnHand,reserved:.quantityReserved}]}'
```

**預期**：至少一筆 `inventoryItems` 記錄（e.g. productId=3, onHand≥5, reserved=0）。

若無庫存記錄，執行補齊腳本（見附錄 A）。

### 0-4. Android 工具鏈 / 執行環境確認

**選項 A（推薦）：Android Emulator**

| 步驟 | 命令 |
|------|------|
| 確認 Flutter 可偵測 emulator | `flutter devices` |
| 啟動 AVD | Android Studio → Device Manager → Start |
| 確認 API URL 設定 | `API_BASE_URL` 必須為 `http://10.0.2.2:3000`（emulator 的 host loopback）|

```bash
# Emulator 專用啟動命令
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
  -d emulator-5554
```

**選項 B：實體 Android 裝置（USB 除錯）**

```bash
adb devices              # 確認裝置已連線
HOST_IP=$(ipconfig | grep "IPv4" | head -1 | awk '{print $NF}')
# e.g. HOST_IP=192.168.1.100
flutter run \
  --dart-define=API_BASE_URL=http://${HOST_IP}:3000 \
  -d <device_id>
```

> **注意**：`localhost:3000` 僅在 App 與後端同一機器（Windows）的 PC 瀏覽器有效；  
> Emulator/Device 必須使用 `10.0.2.2` 或 Host IP。

**若尚未建立 Android Runner**：

```bash
cd packages/frontend
flutter create --platforms=android .   # 產生 android/ 目錄
# 確認 android/app/build.gradle minSdkVersion >= 21
flutter doctor -v                      # 確認 Android toolchain 全綠
```

> `android/` 目錄產生後應納入版控（不含 build/ 資料夾，已在 .gitignore）。

---

## Phase 1：離線建單（Airplane Mode）

> 模擬業務在無網路環境（外訪客戶時）建立完整訂單。

### 1-1. 開啟 App，登入 sales_test

- username: `sales_test` / password: `P@ssw0rd!`
- 登入後確認左上角無錯誤 SnackBar

### 1-2. 切換 Airplane Mode

- 裝置設定 → 開啟飛航模式（中斷網路）

### 1-3. 建立客戶（Tab 1）

- 點 FAB → 填入客戶名（e.g. `走路測試客戶`）→ 儲存
- 確認列表出現新客戶，左側 ☁️ 橘色圖示（離線）
- 記錄 local id（負數，e.g. `-1`）

### 1-4. 建立報價（Tab 3）

- 點 FAB → 選擇「走路測試客戶」
- 新增商品行：選 productId=3 的商品，數量填 `3`
- 確認稅額計算正確（含稅 5%）
- 點儲存

### 1-5. 報價轉訂單（Tab 3）

- 在報價列表找到剛建立的報價 → 點「轉訂單」
- 確認 Tab 4（訂單）出現新訂單，status=pending，☁️ 橘色

### 1-6. 驗證 pending_operations（本地 DB）

此步驟確認離線佇列正確：

| 預期 pending_operations 筆數 | 操作 |
|------------------------------|------|
| 1 筆 `customer:create` | 客戶建立 |
| 1 筆 `quotation:create` | 報價建立 |
| 1 筆 `sales_order:create` | 訂單建立 |
| 共 3 筆 | （無 reserve delta，符合 #12 設計）|

---

## Phase 2：同步 Push

### 2-1. 關閉 Airplane Mode，觸發同步

- 裝置設定 → 關閉飛航模式
- App Tab 4 → 下拉（Pull-to-refresh）

### 2-2. 觀察 Push 結果

- 所有 ☁️ 橘色圖示 → ✅ 綠色（id 轉為正數）
- 無紅色錯誤 SnackBar

### 2-3. 服務端確認（curl）

```bash
# 確認客戶已同步
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/sync/pull?entityTypes=customer&since=2020-01-01T00:00:00Z" \
  | jq '.customers[] | select(.name=="走路測試客戶") | {id, name}'

# 確認報價已同步（含 items）
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/sync/pull?entityTypes=quotation&since=2020-01-01T00:00:00Z" \
  | jq '.quotations[-1] | {id, status, items}'

# 確認訂單已同步
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/sync/pull?entityTypes=sales_order&since=2020-01-01T00:00:00Z" \
  | jq '.salesOrders[-1] | {id, status, quotationId}'
```

**預期**：三筆資料均出現，status 分別為 `active` / `pending`。

---

## Phase 3：確認訂單 + 預留庫存

### 3-1. 確認訂單（Issue #12 新流程）

- Tab 4 → 找到剛同步的訂單（status=pending）
- 點「確認訂單」→ AlertDialog 出現 → 確認文字正確
- 點「確認訂單」（FilledButton）
- 觀察 status Chip → pending（灰）→ confirmed（藍）

### 3-2. 驗收：無 reserve enqueue

- 訂單確認後，pending_operations 中 **不應**出現 `inventory_delta:reserve`
- 只有 `sales_order:update`（status=confirmed）

### 3-3. 預留庫存（Issue #12 新流程）

- 同筆訂單（status=confirmed）→ 出現「預留庫存」按鈕（靛藍）
- 點「預留庫存」→ `ReserveInventoryDialog` 出現
- 確認顯示：產品名 + SKU + 預留數量 3 + 可出貨（onHand - reserved）
- 若庫存充足 → 無 ⚠️ 警示
- 點「確認預留」

### 3-4. Push + 服務端確認

```bash
# 下拉同步（或等待自動）
# 確認 inventoryItems reservedQty 增加 3

BEFORE_RESERVED=0   # 已知初始值
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/sync/pull?entityTypes=inventory_delta" \
  | jq '.inventoryItems[] | select(.productId==3) | {quantityOnHand, quantityReserved}'
# 預期：quantityReserved = BEFORE_RESERVED + 3
```

---

## Phase 4：出貨

### 4-1. 切換 warehouse_test 帳號（或用 admin_test）

> `warehouse_test` 才有出貨按鈕（role=warehouse/admin）

- 登出 → 重新登入 `warehouse_test` / `P@ssw0rd!`
- 或用 `admin_test`（同樣有出貨權限）

### 4-2. 出貨（Issue #13 新流程）

- Tab 4 → 找到 confirmed 訂單 → 點「出貨」
- `ShipOrderDialog` 出現，確認顯示：
  - 出貨數量 3（藍）
  - 在庫 onHand → onHand-3（綠）
  - 預留 reserved → reserved-3 = 0（灰，無警示）
- 點「確認出貨」（綠色 FilledButton）
- status Chip → confirmed（藍）→ shipped（綠）

### 4-3. Push + 服務端最終確認

```bash
# 最終庫存驗收
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/sync/pull?entityTypes=inventory_delta" \
  | jq '.inventoryItems[] | select(.productId==3) | {quantityOnHand, quantityReserved}'
```

**預期（設初始 onHand=H, reserved=0, qty=3）**：

| 時間點 | quantityOnHand | quantityReserved |
|--------|----------------|------------------|
| 初始   | H              | 0                |
| reserve 後 | H          | 3                |
| out 後 | H-3            | 0                | ← **最終期望** |

---

## Phase 5：Pull 驗收（最終一致性）

```bash
# App 端：Tab 5（庫存）→ 下拉 Pull-to-refresh
# 確認本地快照與服務端一致

# 服務端最終全量快照
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v1/sync/pull?since=2020-01-01T00:00:00Z" \
  | jq '{
    customers: [.customers[]|{id,name}],
    quotations: [.quotations[]|{id,status}],
    salesOrders: [.salesOrders[]|{id,status}],
    inventory: [.inventoryItems[]|{productId,onHand:.quantityOnHand,reserved:.quantityReserved}]
  }'
```

---

## Phase 6：邊界情境（選做，時間允許）

| 情境 | 操作 | 預期 |
|------|------|------|
| 未 reserve 直接出貨 | 跳過 Phase 3-3 直接出貨 | ShipOrderDialog 顯示 ⚠️ 警示（reserved < qty）|
| 出貨後服務端拒絕 | Push → INSUFFICIENT_STOCK → 409 | Force Pull，App 顯示正確庫存 |
| 重複 reserve | 同筆訂單再次點「預留庫存」| 服務端 INSUFFICIENT_STOCK（reserved 超過 onHand）|
| First-to-Sync wins | 兩裝置對同一報價轉訂單 | 第二筆 FORBIDDEN_OPERATION |

---

## 通過標準

| 檢查項目 | 通過條件 |
|---------|---------|
| 離線三筆 pending_operations | customer/quotation/sales_order，無 reserve |
| Push 全部 succeeded | 無 failed[] |
| 確認訂單後無 reserve enqueue | DB pending_operations 不含 inventory_delta |
| ReserveInventoryDialog 庫存預覽 | 數字與服務端一致（±0，快照時間接近）|
| ShipOrderDialog 雙欄顯示 | onHand 與 reserved 均顯示 → 值 |
| 最終 quantityOnHand | = 初始 - 出貨數量 |
| 最終 quantityReserved | = 0 |
| App 端 Pull 後庫存顯示 | 與服務端一致 |

---

## 依賴關係

```
Phase 0（環境 + 後端 + 裝置）
  ↓
Phase 1（離線建單）← Airplane Mode
  ↓
Phase 2（Push + 服務端確認）
  ↓
Phase 3（確認訂單 + 預留庫存）
  ↓
Phase 4（出貨）
  ↓
Phase 5（Pull 最終驗收）
  ↓
Phase 6（邊界情境，選做）
```

---

## 附錄 A：無庫存記錄時的初始化腳本

若 Phase 0-3 確認無 inventoryItems 資料，需先透過 Drizzle Studio 或 psql 直接插入：

```sql
-- psql 方式（需連線 Docker PostgreSQL）
INSERT INTO inventory_items (product_id, warehouse_id, quantity_on_hand, quantity_reserved, min_stock_level)
VALUES (3, 1, 15, 0, 2)
ON CONFLICT DO NOTHING;
```

或透過 curl 用 `in` delta 補充（需 warehouseId 欄位已有基礎記錄）：

```bash
# 若已有 inventoryItem 記錄但 onHand=0，用 in delta 補充
curl -X POST http://localhost:3000/api/v1/sync/push \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "operations": [{
      "id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
      "entityType": "inventory_delta",
      "operationType": "delta_update",
      "deltaType": "in",
      "createdAt": "2026-04-13T10:00:00.000Z",
      "payload": {"productId": 3, "amount": 15}
    }]
  }'
# 注意：此操作需用 warehouse_test JWT（role=warehouse）
```

---

## 附錄 B：Android Runner 建立後的 .gitignore 確認

```
# android/ runner 已納入版控
# 以下應已在 .gitignore：
android/.gradle/
android/app/build/
```

執行 `flutter create --platforms=android .` 後，確認 `.gitignore` 涵蓋上述路徑。
