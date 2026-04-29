# Schema Mapping — Knowledge Card Fields

## Products（商品）

| DB 欄位 | Card 標籤 | 包含 | 備註 |
|---|---|---|---|
| id | entity_id (frontmatter) | ✓ | 主鍵 |
| sku | SKU | ✓ | |
| name | 名稱 | ✓ | |
| unit_price | 單價 | ✓ | |
| cost_price | — | ✗ | **黑名單**：進貨成本，商業機密 |
| min_stock_level | 最低庫存水位 | ✓ | |
| created_at / updated_at / deleted_at | — | ✗ | 系統欄位 |

## Customers（客戶）

| DB 欄位 | Card 標籤 | 包含 | 備註 |
|---|---|---|---|
| id | entity_id (frontmatter) | ✓ | 主鍵 |
| name | 名稱 | ✓ | |
| contact | 聯絡人 | ✓ | nullable |
| payment_terms_days | 付款天數 | ✓ | |
| email | — | ✗ | **黑名單**：個人資料 |
| tax_id | — | ✗ | **黑名單**：統一編號 |
| created_at / updated_at / deleted_at | — | ✗ | 系統欄位 |

## Role 可見性

| entity_type | role_admin | role_sales | role_warehouse |
|---|---|---|---|
| product | true | true | true |
| customer | true | true | **false** |

## 敏感欄位黑名單

永不寫入卡片（在 `card_generator.py` generator 層排除，不靠後續 filter）：

- `email` — 個人資料保護
- `tax_id` — 統一編號
- `cost_price` — 進貨成本（商業機密；未來若需 admin-only 欄位需另建 `role_admin_only` metadata 機制）

## 備註

- `cost_price` 暫時排除，因目前 card 格式無 admin-only 欄位遮罩機制
- Warehouse role 不得取得任何 customer card（BM25 corpus 亦不含 customer docs）
