"""Generate knowledge card .md files from the database.

Usage:
    DB_READONLY_URL=postgresql://... python -m src.indexing.card_generator \\
        --output-dir data/knowledge_cards

Sensitive fields (email, tax_id, cost_price) are excluded at this layer.
"""
import os
import sys
from pathlib import Path

import psycopg2

_PRODUCT_SQL = """
SELECT id, sku, name, unit_price, min_stock_level
FROM products
WHERE deleted_at IS NULL
ORDER BY id
"""

_CUSTOMER_SQL = """
SELECT id, name, contact, payment_terms_days
FROM customers
WHERE deleted_at IS NULL
ORDER BY id
"""


def generate_product_cards(cursor, output_dir: str) -> int:
    out = Path(output_dir) / "products"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.md"):
        f.unlink()

    cursor.execute(_PRODUCT_SQL)
    rows = cursor.fetchall()
    for entity_id, sku, name, unit_price, min_stock_level in rows:
        content = (
            f"---\n"
            f"entity_type: product\n"
            f"entity_id: {entity_id}\n"
            f"role_admin: true\n"
            f"role_sales: true\n"
            f"role_warehouse: true\n"
            f"source: db\n"
            f"---\n"
            f"# {name}\n"
            f"SKU：{sku}\n"
            f"名稱：{name}\n"
            f"單價：{unit_price}\n"
            f"最低庫存水位：{min_stock_level}\n"
        )
        (out / f"{sku}.md").write_text(content, encoding="utf-8")
    return len(rows)


def generate_customer_cards(cursor, output_dir: str) -> int:
    out = Path(output_dir) / "customers"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.md"):
        f.unlink()

    cursor.execute(_CUSTOMER_SQL)
    rows = cursor.fetchall()
    for entity_id, name, contact, payment_terms_days in rows:
        contact_line = f"聯絡人：{contact}\n" if contact else ""
        content = (
            f"---\n"
            f"entity_type: customer\n"
            f"entity_id: {entity_id}\n"
            f"role_admin: true\n"
            f"role_sales: true\n"
            f"role_warehouse: false\n"
            f"source: db\n"
            f"---\n"
            f"# {name}\n"
            f"客戶 ID：{entity_id}\n"
            f"名稱：{name}\n"
            f"{contact_line}"
            f"付款天數：{payment_terms_days}\n"
        )
        (out / f"customer_{entity_id:03d}.md").write_text(content, encoding="utf-8")
    return len(rows)


def generate_cards(db_url: str, output_dir: str) -> None:
    conn = psycopg2.connect(db_url)
    try:
        cur = conn.cursor()
        n_p = generate_product_cards(cur, output_dir)
        n_c = generate_customer_cards(cur, output_dir)
        print(f"Generated {n_p} product cards, {n_c} customer cards → {output_dir}")
    finally:
        conn.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate knowledge cards from DB")
    parser.add_argument("--db-url", default=os.getenv("DB_READONLY_URL"))
    parser.add_argument("--output-dir", default="data/knowledge_cards")
    args = parser.parse_args()
    if not args.db_url:
        print("Error: DB_READONLY_URL env var or --db-url required", file=sys.stderr)
        sys.exit(1)
    generate_cards(args.db_url, args.output_dir)
