# ADR-008：物料主檔採購數量限制標準（SPQ / MOQ / lineNotes）

**日期**：2026-05-26  
**狀態**：已採用  
**決策者**：Phase 4 採購流程設計審查

---

## 背景

電子元件採購存在嚴格的「包裝倍數限制」，供應商以整盤（Reel）、整托盤（Tray）、整箱（Box）為最小出貨單位，拆盤/切帶會產生溢價 30–100%。ERP 的報價（Quotation）與採購建議（Planned Order）若不遵守這些限制，會造成：

1. **實際下單數量與系統數字不一致**（須人工修改）
2. **總價計算錯誤**（數量以個計、實際以盤計）
3. **庫存餘料積壓**（下單整盤但需求不足一盤）

傳統 ERP（SAP / Oracle）將上述限制集中在以下兩個模組：

| ERP 模組 | 欄位 | 用途 |
|----------|------|------|
| **物料主檔 (Item Master)** | MOQ、Order Multiple (SPQ) | 全域的採購單位限制 |
| **採購資訊記錄 (Purchasing Info Record)** | Vendor MOQ、Contracted Pack Size | 特定供應商的包裝條件 |
| **MRP 參數** | Lot Sizing Policy | 系統自動計畫時的四捨五入規則 |

MRP 的數量計算流程為：

```
淨需求量 (Net Requirement)
  → 若 < MOQ × SPQ，提升至 MOQ × SPQ
  → 若不為 SPQ 倍數，進位至最近的 SPQ 整數倍 (Round Up)
  → 產生計畫訂單 (Planned Order)
```

本系統目前尚無 MRP 模組，但報價單（Quotation）是採購意圖最早的記錄點，需在此階段就強制整盤下單。

---

## 決策

### 1. `products` 表即為本系統的「物料主檔 (Item Master)」

新增兩個採購條件欄位至 `products` table（Migration 0014）：

| 欄位 | 型別 | 說明 |
|------|------|------|
| `spq` | `integer NOT NULL DEFAULT 1` | Standard Package Quantity：每組/整盤/整捲的零件件數 |
| `moq` | `integer NOT NULL DEFAULT 1` | Minimum Order Quantity：最少下單組數（實際最小件數 = moq × spq） |

**位置設定原則（無需額外操作）**：
- `products.spq` / `products.moq` 在 ERP 產品設定頁面（Item Master 區塊）維護
- 每次新增/修改產品時，採購條件（SPQ/MOQ）應與基本資料一起填寫
- 系統在產生 Quotation 明細時，驗證 `quantity % spq == 0 && quantity/spq >= moq`

### 2. 報價明細的整盤下單標準

Quotation line item（`order_items` with `quotationId`）採用以下規則：

```
下單件數 = N 組 × SPQ（N ≥ MOQ）
單價     = products.unitPrice（per piece 或 per reel，依產品定義）
小計     = quantity × unitPrice
lineNotes = '每組 X pcs'（X = products.spq，當 spq > 1 時必填）
```

**被動元件例外**：`PASS-*`、`LED-*` 系列的 `unitPrice` 已為整盤單價（per reel），非個別單件價；`spq` 在此為「資訊性欄位」，記錄每盤件數，供前端顯示「N 盤 × X pcs = 總件數」。

### 3. `order_items.lineNotes` 欄位（Migration 0014）

```
line_notes VARCHAR(500) NULL
```

**必填條件**：`products.spq > 1` 的報價明細必須填入 `lineNotes`  
**格式**：`每組 X pcs`（X = spq，千分位格式）  
**範例**：`每組 5,000 pcs`、`每組 1,000 pcs`、`每組 50 pcs`

銷售訂單明細（`salesOrderId` 非 null 的行）`lineNotes` 為 `NULL`（倍數限制在報價階段執行，轉訂單後不重複顯示）。

---

## 比較的方案

| 方案 | 描述 | 排除原因 |
|------|------|---------|
| A：不改 schema，僅靠產品名稱 | 以 `(Reel/5K)` 字串傳達包裝 | 無法被程式驗證，命名不一致 |
| **B（採用）：`spq`/`moq` 加入 products** | 物料主檔集中管理，程式可驗證 | — |
| C：獨立 `purchasing_conditions` 表 | 仿 SAP Purchasing Info Record | 目前無多供應商需求，過度設計 |
| D：前端純 UI 提示，不入 DB | 快速，但資料無持久性 | 無法在 MRP/預測模組中使用 |

方案 C 保留為「未來升級路徑」（見下方）。

---

## 理由

- `products` 表是本系統最接近「物料主檔」的實體，在此加欄位符合 ERP 領域慣例，零額外操作
- `DEFAULT 1` 確保向下相容：既有產品（管材、鋼材等）不受影響，個別單件下單行為不變
- `lineNotes` 採可空設計，銷售訂單明細不受影響（現有 seed 資料無需修改）
- 整盤標示寫入產品名稱（`Tray/1K`、`Reel/5K`）與 `lineNotes` 雙軌保存：名稱供快速瀏覽，lineNotes 供報價單列印

---

## 後果

**正面**
- 前端報價單明細可依 `lineNotes` 顯示「N 組 × X pcs = 總件數」，清楚傳達採購數量
- MRP 未來實作時，`spq`/`moq` 已就位，可直接套用進位邏輯
- 庫存盤點模組可利用 `spq` 驗證入庫數量是否為整盤

**負面 / 注意**
- **單位混淆風險**（ERP 常見坑）：
  - `PASS-*` 系列：`unitPrice` = 整盤單價，`quantity` = 盤數
  - 其他所有產品：`unitPrice` = 單件單價，`quantity` = 件數
  - 若兩種計價方式在 UI 上未明確區分，使用者容易混淆
  - **建議**：前端在顯示報價明細時，若 `lineNotes` 存在則以「N 組 @ $X/件」格式呈現；若不存在則顯示「N 件 @ $X」
- `moq` 目前全設為 1，未來若供應商要求 MOQ > 1（如 LiPo 電池最少 5 箱）需人工更新
- 不支援「同一產品多個供應商不同 SPQ」的情境（需升級至方案 C）

---

## 未來升級路徑（不影響現在決策）

若未來引入多供應商或 MRP 模組：

1. **新增 `vendor_purchasing_conditions` 表**（方案 C）
   ```sql
   -- 供應商特定的採購條件（仿 SAP Purchasing Info Record）
   CREATE TABLE vendor_purchasing_conditions (
     id          SERIAL PRIMARY KEY,
     tenant_id   INTEGER NOT NULL,
     product_id  INTEGER NOT NULL REFERENCES products(id),
     vendor_name VARCHAR(255) NOT NULL,
     vendor_spq  INTEGER NOT NULL DEFAULT 1,
     vendor_moq  INTEGER NOT NULL DEFAULT 1,
     effective_date DATE
   );
   ```
   `products.spq` / `products.moq` 降格為「預設值」，優先使用供應商特定條件。

2. **MRP Lot Sizing Policy**：在 MRP 計算時，取 `vendor_spq`（或 `products.spq`）對淨需求量做 `CEIL(need / spq) * spq` 進位運算。

3. **定期校準提醒（ADR-008 的維護義務）**：供應商更改包裝規格時（如從 5K/盤改為 4K/盤），**必須同步更新** `products.spq` 與 `products.name` 中的 `(Reel/XK)` 標示，否則系統會持續產生錯誤的採購建議。

---

## 實作記錄（2026-05-26）

| 異動項目 | 路徑 |
|----------|------|
| Schema：新增 `spq`、`moq` | `packages/backend/src/schemas/products.schema.ts` |
| Schema：新增 `lineNotes` | `packages/backend/src/schemas/order_items.schema.ts` |
| Migration | `packages/backend/drizzle/0014_spq_moq_line_notes.sql` |
| Seed 產品（20項，含整盤標示） | `packages/backend/scripts/seed-production-en.ts` Step 2 |
| Seed 報價明細（39 筆，SPQ-aligned） | `packages/backend/scripts/seed-production-en.ts` Step 6b |

---

## 相關文件

- `LOG/db/Product Sample .md`（電子元件 SPQ/MOQ 參考表，原始知識來源）
- `ADR-001-lww-conflict-resolution.md`（Sync 衝突解法，與訂單數量變更有關）
- `packages/backend/drizzle/0014_spq_moq_line_notes.sql`
