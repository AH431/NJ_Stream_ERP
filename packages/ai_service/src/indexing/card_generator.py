"""Generate rich knowledge card .md files from DB + static catalog metadata.

Usage:
    DB_READONLY_URL=postgresql://... python -m src.indexing.card_generator \
        --output-dir data/knowledge_cards

Two-layer architecture:
  Layer 1 (DB): price, stock quantities, stock levels, contact name, payment terms.
  Layer 2 (catalog): category, aliases, description, specs, use, suppliers, substitutes, notes, QA.

Sensitive fields (email, tax_id, cost_price) are excluded at this layer.
"""
import os
import sys
from datetime import date
from pathlib import Path
from typing import Any

import psycopg2
import yaml

_CATALOG_DIR = Path(__file__).parent.parent.parent / "data"

# inventory_items columns: quantity_on_hand, quantity_reserved,
#   min_stock_level, alert_stock_level, critical_stock_level
_PRODUCT_SQL = """
SELECT
    p.id,
    p.sku,
    p.name,
    p.unit_price,
    COALESCE(ii.quantity_on_hand, 0)    AS qty_on_hand,
    COALESCE(ii.quantity_reserved, 0)   AS qty_reserved,
    COALESCE(ii.min_stock_level, 0)     AS min_stock,
    COALESCE(ii.alert_stock_level, 0)   AS alert_stock,
    COALESCE(ii.critical_stock_level, 0) AS critical_stock
FROM products p
LEFT JOIN inventory_items ii
    ON ii.product_id = p.id AND ii.deleted_at IS NULL
WHERE p.deleted_at IS NULL
ORDER BY p.id
"""

_CUSTOMER_SQL = """
SELECT id, name, contact, payment_terms_days
FROM customers
WHERE deleted_at IS NULL
ORDER BY id
"""


def _load_catalog(filename: str, key_field: str) -> dict[str, Any]:
    path = _CATALOG_DIR / filename
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as f:
        items = yaml.safe_load(f) or []
    return {item[key_field]: item for item in items if key_field in item}


def _fmt_list(items: list | None, fallback: str = "—") -> str:
    if not items:
        return fallback
    return "\n".join(f"- {x}" for x in items)


def _fmt_specs(specs: dict | None) -> str:
    if not specs:
        return "—"
    return "\n".join(f"- **{k}**: {v}" for k, v in specs.items())


def _fmt_qa(qa: list | None) -> str:
    if not qa:
        return "—"
    lines: list[str] = []
    for pair in qa:
        lines.append(f"**Q: {pair.get('q', '')}**")
        lines.append(f"A: {pair.get('a', '')}")
        lines.append("")
    return "\n".join(lines).rstrip()


def _stock_status(qty: int, critical: int, alert: int, min_s: int) -> str:
    if qty <= critical:
        return "CRITICAL — below critical level, urgent reorder required"
    if qty <= alert:
        return "ALERT — below alert level, reorder soon"
    if qty <= min_s:
        return "LOW — below safety level"
    return "OK"


def generate_product_cards(cursor, output_dir: str, catalog: dict[str, Any]) -> int:
    out = Path(output_dir) / "products"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.md"):
        f.unlink()

    cursor.execute(_PRODUCT_SQL)
    rows = cursor.fetchall()
    today = date.today().isoformat()

    for (entity_id, sku, name, unit_price,
         qty_on_hand, qty_reserved, min_stock, alert_stock, critical_stock) in rows:

        meta = catalog.get(sku, {})
        category = meta.get("category", "component")
        available = int(qty_on_hand) - int(qty_reserved)
        status = _stock_status(int(qty_on_hand), int(critical_stock), int(alert_stock), int(min_stock))

        aliases = meta.get("aliases", [])
        aliases_inline = ", ".join(aliases) if aliases else "—"

        frontmatter = (
            f"---\n"
            f"entity_type: product\n"
            f"entity_id: {entity_id}\n"
            f"sku: {sku}\n"
            f"category: {category}\n"
            f"role_admin: true\n"
            f"role_sales: true\n"
            f"role_warehouse: true\n"
            f"source: db+catalog\n"
            f"---\n"
        )

        body = f"""# {name} ({sku})

## Product Identity
- **SKU**: {sku}
- **Name**: {name}
- **Category**: {category}
- **Also known as**: {aliases_inline}

## Description
{meta.get("description", "—").strip()}

## Specifications
{_fmt_specs(meta.get("common_specs"))}

## Inventory Status
- **On Hand**: {int(qty_on_hand)} units
- **Reserved**: {int(qty_reserved)} units
- **Available**: {available} units
- **Safety Level**: {min_stock} | Alert: {alert_stock} | Critical: {critical_stock}
- **Status**: {status}

## Pricing
- **Unit Price**: ${unit_price}

## Typical Applications
{_fmt_list(meta.get("typical_use"))}

## Suppliers
{_fmt_list(meta.get("suppliers"))}

## Substitutes / Alternatives
{_fmt_list(meta.get("substitutes"))}

## Notes
{meta.get("notes", "—").strip()}

## Q&A
{_fmt_qa(meta.get("qa"))}

## Last Updated
{today}
"""
        (out / f"{sku}.md").write_text(frontmatter + body, encoding="utf-8")

    return len(rows)


def generate_customer_cards(cursor, output_dir: str, catalog: dict[str, Any]) -> int:
    out = Path(output_dir) / "customers"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.md"):
        f.unlink()

    cursor.execute(_CUSTOMER_SQL)
    rows = cursor.fetchall()
    today = date.today().isoformat()

    for entity_id, name, contact, payment_terms_days in rows:
        meta = catalog.get(name, {})

        frontmatter = (
            f"---\n"
            f"entity_type: customer\n"
            f"entity_id: {entity_id}\n"
            f"role_admin: true\n"
            f"role_sales: true\n"
            f"role_warehouse: false\n"
            f"source: db+catalog\n"
            f"---\n"
        )

        contact_line = f"- **Primary Contact**: {contact}" if contact else "- Contact details available via dynamic API."

        body = f"""# {name}

## Customer Identity
- **Name**: {name}
- **Customer ID**: {entity_id}

## Contact Summary
{contact_line}

## Payment Terms
- **Net Days**: {payment_terms_days} days

## Industry / Segment
{meta.get("segment", "—").strip()}

## Preferred Products
{_fmt_list(meta.get("preferred_products"))}

## Account Notes
{meta.get("account_notes", "—").strip()}

## Common Asks / FAQ
{_fmt_qa(meta.get("common_asks"))}

## Last Updated
{today}
"""
        (out / f"customer_{entity_id:03d}.md").write_text(frontmatter + body, encoding="utf-8")

    return len(rows)


def generate_cards(db_url: str, output_dir: str) -> None:
    product_catalog = _load_catalog("product_catalog.yaml", key_field="sku")
    customer_catalog = _load_catalog("customer_catalog.yaml", key_field="name")

    conn = psycopg2.connect(db_url)
    try:
        cur = conn.cursor()
        n_p = generate_product_cards(cur, output_dir, product_catalog)
        n_c = generate_customer_cards(cur, output_dir, customer_catalog)
        print(f"Generated {n_p} product cards, {n_c} customer cards → {output_dir}")
    finally:
        conn.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate rich knowledge cards from DB + catalog")
    parser.add_argument("--db-url", default=os.getenv("DB_READONLY_URL"))
    parser.add_argument("--output-dir", default="data/knowledge_cards")
    args = parser.parse_args()
    if not args.db_url:
        print("Error: DB_READONLY_URL env var or --db-url required", file=sys.stderr)
        sys.exit(1)
    generate_cards(args.db_url, args.output_dir)
