"""
Tests for src/indexing/card_generator.py.
psycopg2 is fully mocked — no DB connection required.
"""
from decimal import Decimal
from pathlib import Path
from unittest.mock import MagicMock, patch

import frontmatter
import pytest

from src.indexing.card_generator import generate_cards

_PRODUCTS = [(1, "IC-8800", "IC 工業控制器 8800", Decimal("12500.00"), 5)]
_CUSTOMERS = [(1, "台灣科技股份有限公司", "王大明", 30)]


def _run(tmp_path: Path) -> None:
    with patch("src.indexing.card_generator.psycopg2") as mock_pg:
        mock_conn = MagicMock()
        mock_pg.connect.return_value = mock_conn
        mock_cur = MagicMock()
        mock_conn.cursor.return_value = mock_cur
        mock_cur.fetchall.side_effect = [_PRODUCTS, _CUSTOMERS]
        generate_cards("postgresql://fake/testdb", str(tmp_path))


def test_generates_files(tmp_path):
    _run(tmp_path)
    assert len(list((tmp_path / "products").glob("*.md"))) == 1
    assert len(list((tmp_path / "customers").glob("*.md"))) == 1


def test_no_sensitive_fields(tmp_path):
    _run(tmp_path)
    for md_file in tmp_path.rglob("*.md"):
        content = md_file.read_text(encoding="utf-8").lower()
        assert "email" not in content
        assert "tax_id" not in content
        assert "cost_price" not in content


def test_product_card_schema_compliance(tmp_path):
    _run(tmp_path)
    card = next((tmp_path / "products").glob("*.md"))
    post = frontmatter.load(str(card))
    assert post.metadata["entity_type"] == "product"
    assert post.metadata["role_admin"] is True
    assert post.metadata["role_sales"] is True
    assert post.metadata["role_warehouse"] is True
    assert post.metadata["source"] == "db"


def test_customer_card_warehouse_false(tmp_path):
    _run(tmp_path)
    card = next((tmp_path / "customers").glob("*.md"))
    post = frontmatter.load(str(card))
    assert post.metadata["entity_type"] == "customer"
    assert post.metadata["role_admin"] is True
    assert post.metadata["role_sales"] is True
    assert post.metadata["role_warehouse"] is False


def test_product_card_contains_required_fields(tmp_path):
    _run(tmp_path)
    card = next((tmp_path / "products").glob("*.md"))
    content = card.read_text(encoding="utf-8")
    assert "IC-8800" in content
    assert "12500" in content
    assert "最低庫存水位" in content


def test_customer_card_no_email_or_tax_id(tmp_path):
    """Regression: even if the DB row somehow had email/tax_id they must not appear."""
    _run(tmp_path)
    card = next((tmp_path / "customers").glob("*.md"))
    content = card.read_text(encoding="utf-8").lower()
    assert "email" not in content
    assert "tax_id" not in content
