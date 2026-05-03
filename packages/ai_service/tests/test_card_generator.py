"""
Tests for src/indexing/card_generator.py — v2 rich cards.
psycopg2 is fully mocked; no DB connection required.
"""
from decimal import Decimal
from pathlib import Path
from unittest.mock import MagicMock, patch

import frontmatter
import pytest

from src.indexing.card_generator import _stock_status, generate_cards

# ── Mock DB rows ─────────────────────────────────────────────────────────────
# (entity_id, sku, name, unit_price, qty_on_hand, qty_reserved,
#  min_stock, alert_stock, critical_stock)
_P_CATALOG = (
    1, "MCU-STM32F103C8", "STM32F103C8T6 Microcontroller",
    Decimal("4.50"), 280, 30, 200, 100, 60,
)
_P_NO_CATALOG = (
    2, "UNKNOWN-SKU-9999", "Generic Test Part",
    Decimal("1.00"), 500, 0, 100, 50, 20,
)
_P_LOW_STOCK = (
    3, "COMM-NRF52840-MOD", "nRF52840 BLE 5.0 SoC Module",
    Decimal("9.50"), 65, 15, 80, 40, 24,
)

# (entity_id, name, contact, payment_terms_days)
_C_TECHNOVA = (1, "TechNova Devices Inc.", "Sarah Chen", 30)
_C_BARE = (2, "NoSuchCustomer Corp.", "John Doe", 45)


def _run(tmp_path: Path, products=None, customers=None) -> None:
    if products is None:
        products = [_P_CATALOG]
    if customers is None:
        customers = [_C_TECHNOVA]
    with patch("src.indexing.card_generator.psycopg2") as mock_pg:
        mock_conn = MagicMock()
        mock_pg.connect.return_value = mock_conn
        mock_cur = MagicMock()
        mock_conn.cursor.return_value = mock_cur
        mock_cur.fetchall.side_effect = [list(products), list(customers)]
        generate_cards("postgresql://fake/testdb", str(tmp_path))


# ── File generation ───────────────────────────────────────────────────────────

def test_generates_one_product_and_one_customer(tmp_path):
    _run(tmp_path)
    assert len(list((tmp_path / "products").glob("*.md"))) == 1
    assert len(list((tmp_path / "customers").glob("*.md"))) == 1


def test_two_products_produce_two_files(tmp_path):
    _run(tmp_path, products=[_P_CATALOG, _P_NO_CATALOG])
    assert len(list((tmp_path / "products").glob("*.md"))) == 2


# ── Sensitive field exclusion ─────────────────────────────────────────────────

def test_no_sensitive_fields_in_any_card(tmp_path):
    _run(tmp_path, products=[_P_CATALOG, _P_NO_CATALOG], customers=[_C_TECHNOVA, _C_BARE])
    for md_file in tmp_path.rglob("*.md"):
        body = md_file.read_text(encoding="utf-8").lower()
        assert "email" not in body
        assert "tax_id" not in body
        assert "cost_price" not in body


# ── Product frontmatter ───────────────────────────────────────────────────────

def test_product_frontmatter_catalog_match(tmp_path):
    _run(tmp_path)
    post = frontmatter.load(str(next((tmp_path / "products").glob("*.md"))))
    assert post.metadata["entity_type"] == "product"
    assert post.metadata["sku"] == "MCU-STM32F103C8"
    assert post.metadata["category"] == "microcontroller"
    assert post.metadata["source"] == "db+catalog"
    assert post.metadata["role_admin"] is True
    assert post.metadata["role_sales"] is True
    assert post.metadata["role_warehouse"] is True


def test_product_frontmatter_no_catalog_defaults(tmp_path):
    _run(tmp_path, products=[_P_NO_CATALOG])
    post = frontmatter.load(str(next((tmp_path / "products").glob("*.md"))))
    assert post.metadata["category"] == "component"
    assert post.metadata["source"] == "db+catalog"


# ── Product card body — catalog-enriched ─────────────────────────────────────

def test_product_card_identity_section(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "MCU-STM32F103C8" in content
    assert "STM32F103C8T6 Microcontroller" in content
    assert "## Product Identity" in content


def test_product_card_description_from_catalog(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "## Description" in content
    assert "ARM Cortex-M3" in content


def test_product_card_specs_from_catalog(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "## Specifications" in content
    assert "72 MHz" in content


def test_product_card_aliases_from_catalog(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "Blue Pill MCU" in content


def test_product_card_qa_section_from_catalog(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "## Q&A" in content
    assert "What is MCU-STM32F103C8?" in content


def test_product_card_inventory_section(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "## Inventory Status" in content
    assert "On Hand" in content
    assert "Available" in content
    assert "Safety Level" in content


def test_product_card_pricing_section(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "## Pricing" in content
    assert "4.50" in content


# ── Product card body — bare (no catalog entry) ───────────────────────────────

def test_product_card_bare_fallback_description(tmp_path):
    _run(tmp_path, products=[_P_NO_CATALOG])
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "## Description" in content
    assert "—" in content


# ── Stock status logic ────────────────────────────────────────────────────────

def test_stock_status_ok():
    assert _stock_status(500, 60, 100, 200) == "OK"


def test_stock_status_low():
    assert _stock_status(150, 60, 100, 200).startswith("LOW")


def test_stock_status_alert():
    assert _stock_status(90, 60, 100, 200).startswith("ALERT")


def test_stock_status_critical():
    assert _stock_status(50, 60, 100, 200).startswith("CRITICAL")


def test_stock_status_boundary_at_critical():
    assert _stock_status(60, 60, 100, 200).startswith("CRITICAL")


def test_stock_status_boundary_at_alert():
    assert _stock_status(100, 60, 100, 200).startswith("ALERT")


def test_low_stock_product_shows_low_in_card(tmp_path):
    _run(tmp_path, products=[_P_LOW_STOCK])
    content = next((tmp_path / "products").glob("*.md")).read_text(encoding="utf-8")
    assert "LOW" in content


# ── Customer frontmatter ──────────────────────────────────────────────────────

def test_customer_frontmatter(tmp_path):
    _run(tmp_path)
    post = frontmatter.load(str(next((tmp_path / "customers").glob("*.md"))))
    assert post.metadata["entity_type"] == "customer"
    assert post.metadata["role_admin"] is True
    assert post.metadata["role_sales"] is True
    assert post.metadata["role_warehouse"] is False
    assert post.metadata["source"] == "db+catalog"


# ── Customer card body ────────────────────────────────────────────────────────

def test_customer_card_payment_terms(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "customers").glob("*.md")).read_text(encoding="utf-8")
    assert "Payment Terms" in content
    assert "30" in content


def test_customer_card_segment_from_catalog(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "customers").glob("*.md")).read_text(encoding="utf-8")
    assert "Industry / Segment" in content
    assert "IoT" in content


def test_customer_card_preferred_products_from_catalog(tmp_path):
    _run(tmp_path)
    content = next((tmp_path / "customers").glob("*.md")).read_text(encoding="utf-8")
    assert "Preferred Products" in content
    assert "MCU-ESP32-WROOM32U" in content


def test_customer_card_no_sensitive_fields(tmp_path):
    _run(tmp_path, customers=[_C_TECHNOVA, _C_BARE])
    for card in (tmp_path / "customers").glob("*.md"):
        body = card.read_text(encoding="utf-8").lower()
        assert "email" not in body
        assert "tax_id" not in body
