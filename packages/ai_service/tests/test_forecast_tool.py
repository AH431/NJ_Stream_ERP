"""
test_forecast_tool.py — M5.3 golden eval (5 cases) + formatter unit tests.

Golden questions (GQ-F01 ~ GQ-F05) verify that:
  - query_parser routes to tool='forecast' with correct SKU
  - format_forecast_answer produces expected sections
"""

import pytest
from src.tools.query_parser import parse_question
from src.tools.formatters import format_forecast_answer, format_forecast_not_found


# ── Parser: 5 golden questions ────────────────────────────────────────────────

def test_gq_f01_stockout_weeks():
    """GQ-F01: TUBE-A001 幾週後缺貨？"""
    r = parse_question("TUBE-A001 幾週後缺貨？")
    assert r.route == "dynamic"
    assert r.tool == "forecast"
    assert r.sku == "TUBE-A001"


def test_gq_f02_next_week_demand():
    """GQ-F02: NJ-1001 的下週需求預測？"""
    r = parse_question("NJ-1001 的下週需求預測？")
    assert r.route == "dynamic"
    assert r.tool == "forecast"
    assert r.sku == "NJ-1001"


def test_gq_f03_reorder_needed():
    """GQ-F03: PASS-RES-0402-1K5K 需要補貨嗎？"""
    r = parse_question("PASS-RES-0402-1K5K 需要補貨嗎？")
    assert r.route == "dynamic"
    assert r.tool == "forecast"
    assert r.sku == "PASS-RES-0402-1K5K"


def test_gq_f04_stock_enough():
    """GQ-F04: IC-8800 預測庫存夠嗎？"""
    r = parse_question("IC-8800 預測庫存夠嗎？")
    assert r.route == "dynamic"
    assert r.tool == "forecast"
    assert r.sku == "IC-8800"


def test_gq_f05_stockout_weeks_alt():
    """GQ-F05: 幾週後 TUBE-B002 會缺貨？"""
    r = parse_question("幾週後 TUBE-B002 會缺貨？")
    assert r.route == "dynamic"
    assert r.tool == "forecast"
    assert r.sku == "TUBE-B002"


# ── Parser: forecast must NOT override inventory for plain stock questions ─────

def test_inventory_not_overridden_by_forecast():
    """Plain 庫存 question without forecast keywords → stays inventory."""
    r = parse_question("IC-8800 現在的庫存剩多少？")
    assert r.tool == "inventory"


# ── Formatter: format_forecast_answer ─────────────────────────────────────────

_SAMPLE_DATA_REORDER = {
    "sku": "TUBE-A001",
    "product_id": 1,
    "current_stock": 50,
    "forecasts": [
        {"week_start": "2026-05-27", "qty": 30.0, "lower": 24.0, "upper": 36.0},
        {"week_start": "2026-06-03", "qty": 30.0, "lower": 24.0, "upper": 36.0},
    ],
    "reorder_alert": True,
    "stockout_week": "2026-06-03",
}

_SAMPLE_DATA_OK = {
    "sku": "NJ-1001",
    "product_id": 2,
    "current_stock": 200,
    "forecasts": [
        {"week_start": "2026-05-27", "qty": 10.0, "lower": 8.0, "upper": 12.0},
    ],
    "reorder_alert": False,
    "stockout_week": None,
}


def test_format_forecast_reorder_alert():
    result = format_forecast_answer(_SAMPLE_DATA_REORDER)
    assert "TUBE-A001" in result
    assert "REORDER ALERT" in result
    assert "2026-06-03" in result
    assert "50" in result  # current stock


def test_format_forecast_ok():
    result = format_forecast_answer(_SAMPLE_DATA_OK)
    assert "NJ-1001" in result
    assert "[OK]" in result
    assert "REORDER" not in result


def test_format_forecast_empty():
    data = {**_SAMPLE_DATA_REORDER, "forecasts": [], "reorder_alert": False, "stockout_week": None}
    result = format_forecast_answer(data)
    assert "No forecast data" in result


def test_format_forecast_not_found():
    result = format_forecast_not_found("TUBE-X999")
    assert "TUBE-X999" in result
