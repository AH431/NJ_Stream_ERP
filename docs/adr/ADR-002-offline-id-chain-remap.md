# ADR-002：離線 ID 策略 — 負數本地 ID + 兩段式 FK Remap

**日期**：2026-04-16（Issue #34 實作）  
**狀態**：已採用  
**決策者**：Sprint 4

---

## 背景

離線模式下，前端在本地新增 Customer / Quotation / SalesOrder 時，無法向後端取得真實 ID。
這些本地記錄之間存在 FK 依賴（Quotation.customerId → Customer.id），
若離線時建立一條 Customer → Quotation → SalesOrder 的鏈，
推送後後端產生的正整數 ID 無法自動更新這條鏈，導致資料孤兒。

此問題在 Sprint 3 Walking Test（4/14）被發現為 Bug #2，在 Sprint 4 作為 Issue #34 修復。

---

## 決策

### 本地 ID 策略：負數遞減

```dart
static int _localIdCounter = -1;
static int nextLocalId() => _localIdCounter--;
```

- 離線新增的所有 entity 使用負數 ID（-1, -2, -3, ...）
- 正數 ID 保留給後端確認後的真實 ID
- 前端 UI 以橘色雲端 icon 標示「未同步」狀態

### FK Remap：兩段式映射

**Stage 1 — Push Response 取得映射表**

```
pushResponse.idMappings = [
  { localId: -1, serverId: 42 },   // Customer
  { localId: -2, serverId: 18 },   // Quotation
  { localId: -3, serverId: 7 },    // SalesOrder
]
```

**Stage 2 — 依賴順序更新本地 DB**

```
1. Customer（無上游依賴）：localId=-1 → serverId=42，更新 customers 表
2. Quotation（依賴 Customer）：customerId=-1 → 42，id=-2 → 18，更新 quotations 表
3. SalesOrder（依賴 Quotation）：quotationId=-2 → 18，id=-3 → 7，更新 sales_orders 表
```

更新順序嚴格按照 FK 依賴鏈，避免 FK 約束錯誤。

---

## 理由

| 替代方案 | 排除原因 |
|---------|---------|
| UUID v4 | 無正負數區分，前端無法快速判斷「是否已同步」 |
| Optimistic Lock（推送前不建本地 FK） | UX 差，離線時無法預覽關聯資料 |
| 推送後再建 FK（先存草稿） | 需要複雜的草稿 → 正式 的狀態機 |

負數 ID 策略在 ERP 的離線場景中是成熟的解法，簡單且前端 UI 有明確語意（負數 = 未同步）。

---

## 後果

**正面**
- 前端可立即顯示完整的離線新增資料（Customer、Quotation、Order 都可看到）
- 後端不需要知道本地 ID 的存在
- `idMappings` 只需在 push response 中加一個欄位

**負面**
- Push 失敗時，負數 ID 會留在本地，需要處理重試邏輯
- `_localIdCounter` 是記憶體狀態，App 重啟後從 -1 重開，可能與舊的負數記錄衝突（目前以 DB 最小 ID - 1 作為起始值）

---

## 相關文件

- `LOG/issues/issue14-task.md`（Walking Test，Bug #2 發現）
- `CHANGELOG.md` Sprint 4 — Issue #34