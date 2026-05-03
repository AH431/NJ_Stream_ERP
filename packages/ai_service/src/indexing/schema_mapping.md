# Schema Mapping — Knowledge Card Fields (v2, 2026-05-03)

Two-layer card architecture:
- **Layer 1 (DB)**: price, stock quantities, stock levels, contact, payment terms — read at card-gen time.
- **Layer 2 (catalog)**: category, aliases, description, specs, typical use, suppliers, substitutes, notes, QA — from `data/product_catalog.yaml` and `data/customer_catalog.yaml`.

---

## Products

### DB Fields

| DB table / column | Card section | Included | Notes |
|---|---|---|---|
| `products.id` | frontmatter `entity_id` | ✓ | Primary key |
| `products.sku` | frontmatter `sku` + Product Identity | ✓ | |
| `products.name` | heading + Product Identity | ✓ | |
| `products.unit_price` | Pricing section | ✓ | |
| `products.cost_price` | — | ✗ | **Blacklist**: trade secret |
| `inventory_items.quantity_on_hand` | Inventory Status | ✓ | |
| `inventory_items.quantity_reserved` | Inventory Status | ✓ | |
| `inventory_items.min_stock_level` | Inventory Status | ✓ | Safety threshold |
| `inventory_items.alert_stock_level` | Inventory Status | ✓ | Alert threshold |
| `inventory_items.critical_stock_level` | Inventory Status | ✓ | Critical threshold |
| `products.created_at / updated_at / deleted_at` | — | ✗ | System fields |

### Catalog Fields (product_catalog.yaml)

| YAML field | Card section | Notes |
|---|---|---|
| `category` | frontmatter `category` + Product Identity | |
| `aliases` | Product Identity "Also known as" | Enables alias / synonym retrieval |
| `description` | Description section | Rich natural-language description |
| `common_specs` | Specifications section | Key-value dict |
| `typical_use` | Typical Applications section | Bullet list |
| `suppliers` | Suppliers section | Bullet list |
| `substitutes` | Substitutes / Alternatives section | Bullet list |
| `notes` | Notes section | Free text; include warnings where relevant |
| `qa` | Q&A section | List of `{q, a}` pairs |

---

## Customers

### DB Fields

| DB table / column | Card section | Included | Notes |
|---|---|---|---|
| `customers.id` | frontmatter `entity_id` + Customer Identity | ✓ | Primary key |
| `customers.name` | heading + Customer Identity | ✓ | |
| `customers.contact` | Contact Summary | ✓ | nullable |
| `customers.payment_terms_days` | Payment Terms | ✓ | |
| `customers.email` | — | ✗ | **Blacklist**: personal data |
| `customers.tax_id` | — | ✗ | **Blacklist**: tax identifier |
| `customers.created_at / updated_at / deleted_at` | — | ✗ | System fields |

### Catalog Fields (customer_catalog.yaml)

| YAML field | Card section | Notes |
|---|---|---|
| `segment` | Industry / Segment section | Industry and product focus |
| `preferred_products` | Preferred Products section | Bullet list of SKUs |
| `account_notes` | Account Notes section | Buying patterns, special requirements |
| `common_asks` | Common Asks / FAQ section | List of `{q, a}` pairs |

---

## Frontmatter Fields

| Field | Products | Customers | Notes |
|---|---|---|---|
| `entity_type` | `product` | `customer` | |
| `entity_id` | ✓ | ✓ | DB primary key |
| `sku` | ✓ | — | Product SKU for retrieval |
| `category` | ✓ | — | From catalog |
| `role_admin` | `true` | `true` | |
| `role_sales` | `true` | `true` | |
| `role_warehouse` | `true` | `false` | Warehouse cannot read customer cards |
| `source` | `db+catalog` | `db+catalog` | Both layers used |

---

## Sensitive Field Blacklist

Never written to any card (excluded in `card_generator.py` at generation time):

| Field | Table | Reason |
|---|---|---|
| `email` | customers | Personal data protection |
| `tax_id` | customers | Tax identifier |
| `cost_price` | products | Trade secret — business cost margin |

Contact queries (email, phone) must use the dynamic tool path, not static RAG.

---

## Stock Status Logic

Derived from `inventory_items` thresholds; displayed in Inventory Status section:

| Condition | Status label |
|---|---|
| `qty_on_hand <= critical_stock_level` | CRITICAL — urgent reorder |
| `qty_on_hand <= alert_stock_level` | ALERT — reorder soon |
| `qty_on_hand <= min_stock_level` | LOW — below safety level |
| otherwise | OK |

---

## Output Paths

| Card type | Output directory | Filename pattern |
|---|---|---|
| Product | `data/knowledge_cards/products/` | `{SKU}.md` |
| Customer | `data/knowledge_cards/customers/` | `customer_{id:03d}.md` |
