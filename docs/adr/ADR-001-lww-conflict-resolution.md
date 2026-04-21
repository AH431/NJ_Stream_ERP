# ADR-001：使用 LWW（Last-Write-Wins）作為 Sync 衝突解法

**日期**：2026-04-10  
**狀態**：已採用  
**決策者**：全團隊（Sprint 1）

---

## 背景

多設備離線操作下，同一筆資料可能在不同設備上產生衝突版本。
需要在 Sprint 1 API Contract 凍結前確定衝突解法，因為它影響所有 sync endpoint 的設計。

---

## 決策

使用 **Last-Write-Wins（LWW）**，以 `updatedAt`（UTC ISO8601）作為決定性依據。
後端收到 push operation 時，比較 payload 的 `updatedAt` 與資料庫現有記錄：
- payload 較新 → 覆蓋
- payload 較舊 → 忽略，回傳 `DATA_CONFLICT`，前端強制 Pull

---

## 理由

| 替代方案 | 排除原因 |
|---------|---------|
| CRDT（無衝突複製資料型別） | 實作複雜度過高，MVP 不值得引入 |
| 人工衝突解決（使用者介面） | UX 差，warehouse 人員操作速度慢，ERP 場景不適合 |
| First-to-Sync Wins | 對 ERP 報價轉訂單場景更合適（已採用於 quotation → order 轉換） |

LWW 在企業 ERP 情境下合理：同一商品被兩台設備同時修改的機率低，且 `updatedAt` 精度（毫秒）足以區分。

---

## 後果

**正面**
- 實作簡單，API Contract 一條規則涵蓋所有 entity
- 前端不需要衝突解決 UI
- 合約明確，前後端均可自證符合

**負面**
- 極端情況下（兩台設備在毫秒內修改同一筆資料），較晚的那方更新會被靜默丟棄
- 可接受：企業 ERP 場景下此情境極罕見，且丟棄的是「較早」的更新

---

## 若未來需要改變

1. 將 `updatedAt` 改為 **Vector Clock**（向量時鐘）
2. 前端加入衝突解決 UI，讓使用者選擇保留哪一版本
3. 需要修改 API Contract、SyncProvider、所有 entity 的 push/pull 邏輯

---

## 相關文件

- `docs/NJ_Stream_ERP MVP 同步協定規格 v1.6.md` §3.2 衝突解法
- `docs/api-contract-sync-v1.6.yaml` operationType: update 的 LWW 規則