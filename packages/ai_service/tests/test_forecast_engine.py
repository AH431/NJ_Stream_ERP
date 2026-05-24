"""
test_forecast_engine.py — Unit tests for forecast engine helpers.

Covers 4 fixtures:
  1. Normal (>= FORECAST_MIN_DATA_WEEKS rows)  → returns forecast list
  2. Insufficient data (< FORECAST_MIN_DATA_WEEKS rows) → returns None (skipped)
  3. Single product (exactly FORECAST_MIN_DATA_WEEKS rows) → returns forecast list
  4. Empty DataFrame → returns None (skipped)

Prophet is mocked to keep CI green on Windows (no C++ build tools needed).
"""

import os
import sys
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Ensure src imports resolve when pytest is run from the package root.
PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

os.environ.setdefault("AI_SERVICE_INTERNAL_TOKEN", "test-token")
os.environ.setdefault("DATABASE_URL", "postgresql://test:test@localhost/test")

import pandas as pd

from src.api.forecast import (
    _FORECAST_MIN_DATA_WEEKS,
    _extract_product_ids,
    _fake_predict,
    _next_mondays,
    _prophet_predict,
)


# ── Helpers ───────────────────────────────────────────────────────────────────


def _make_df(n_weeks: int) -> pd.DataFrame:
    today = date.today()
    dates = [(today - timedelta(weeks=n_weeks - i)).strftime("%Y-%m-%d") for i in range(n_weeks)]
    return pd.DataFrame({"week_start": dates, "qty": [float(10 + i) for i in range(n_weeks)]})


def _mock_prophet(weeks_ahead: int):
    """Return a (mock_cls, mock_instance) pair whose predict() returns `weeks_ahead` future rows."""
    today = date.today()
    future_dates = pd.to_datetime(
        [(today + timedelta(weeks=i + 1)).strftime("%Y-%m-%d") for i in range(weeks_ahead)]
    )
    forecast_df = pd.DataFrame({
        "ds":         future_dates,
        "yhat":       [50.0] * weeks_ahead,
        "yhat_lower": [40.0] * weeks_ahead,
        "yhat_upper": [60.0] * weeks_ahead,
    })

    all_dates = pd.to_datetime(
        [(today - timedelta(weeks=8 - i)).strftime("%Y-%m-%d") for i in range(8)]
        + [(today + timedelta(weeks=i + 1)).strftime("%Y-%m-%d") for i in range(weeks_ahead)]
    )

    mock_m = MagicMock()
    mock_m.predict.return_value = forecast_df
    mock_m.make_future_dataframe.return_value = pd.DataFrame({"ds": all_dates})

    mock_cls = MagicMock(return_value=mock_m)
    return mock_cls, mock_m


# ── Fixture 1: Normal (enough data) ──────────────────────────────────────────


class TestProphetPredictNormal:
    @patch("src.api.forecast.Prophet")
    def test_returns_forecast_list(self, mock_prophet_cls):
        weeks_ahead = 12
        mock_cls, _ = _mock_prophet(weeks_ahead)
        mock_prophet_cls.side_effect = mock_cls.side_effect
        mock_prophet_cls.return_value = mock_cls.return_value

        df = _make_df(_FORECAST_MIN_DATA_WEEKS + 4)
        result = _prophet_predict(df, weeks_ahead=weeks_ahead)

        assert result is not None
        assert len(result) == weeks_ahead

    @patch("src.api.forecast.Prophet")
    def test_all_required_keys_present(self, mock_prophet_cls):
        weeks_ahead = 4
        mock_cls, _ = _mock_prophet(weeks_ahead)
        mock_prophet_cls.return_value = mock_cls.return_value

        df = _make_df(_FORECAST_MIN_DATA_WEEKS + 2)
        result = _prophet_predict(df, weeks_ahead=weeks_ahead)

        assert result is not None
        for row in result:
            assert set(row.keys()) >= {"week_start", "forecast_qty", "lower_bound", "upper_bound"}

    @patch("src.api.forecast.Prophet")
    def test_forecast_qty_non_negative(self, mock_prophet_cls):
        weeks_ahead = 6
        mock_cls, mock_m = _mock_prophet(weeks_ahead)
        # Inject negative yhat to verify max(0, ...) clamp
        mock_m.predict.return_value["yhat"] = [-5.0] * weeks_ahead
        mock_prophet_cls.return_value = mock_cls.return_value

        df = _make_df(_FORECAST_MIN_DATA_WEEKS + 2)
        result = _prophet_predict(df, weeks_ahead=weeks_ahead)

        assert result is not None
        for row in result:
            assert row["forecast_qty"] >= 0.0


# ── Fixture 2: Insufficient data ─────────────────────────────────────────────


class TestProphetPredictInsufficientData:
    def test_below_min_returns_none(self):
        df = _make_df(_FORECAST_MIN_DATA_WEEKS - 1)
        result = _prophet_predict(df, weeks_ahead=12)
        assert result is None

    def test_one_row_returns_none(self):
        df = _make_df(1)
        result = _prophet_predict(df, weeks_ahead=12)
        assert result is None

    def test_exactly_min_minus_one_returns_none(self):
        df = pd.DataFrame({
            "week_start": ["2024-01-01"] * (_FORECAST_MIN_DATA_WEEKS - 1),
            "qty":        [10.0]         * (_FORECAST_MIN_DATA_WEEKS - 1),
        })
        result = _prophet_predict(df, weeks_ahead=12)
        assert result is None


# ── Fixture 3: Single product (exactly FORECAST_MIN_DATA_WEEKS rows) ─────────


class TestProphetPredictSingleProduct:
    @patch("src.api.forecast.Prophet")
    def test_exactly_min_weeks_produces_forecast(self, mock_prophet_cls):
        weeks_ahead = 4
        mock_cls, _ = _mock_prophet(weeks_ahead)
        mock_prophet_cls.return_value = mock_cls.return_value

        df = _make_df(_FORECAST_MIN_DATA_WEEKS)
        result = _prophet_predict(df, weeks_ahead=weeks_ahead)

        assert result is not None
        assert len(result) == weeks_ahead


# ── Fixture 4: Empty DataFrame ────────────────────────────────────────────────


class TestProphetPredictEmpty:
    def test_empty_df_returns_none(self):
        df = pd.DataFrame({"week_start": [], "qty": []})
        result = _prophet_predict(df, weeks_ahead=12)
        assert result is None

    def test_all_nan_qty_returns_none(self):
        import math
        df = pd.DataFrame({
            "week_start": ["2024-01-01"] * 3,
            "qty":        [float("nan")] * 3,
        })
        # NaN rows dropped by dropna → fewer than min_data_weeks → None
        result = _prophet_predict(df, weeks_ahead=12)
        assert result is None


# ── _extract_product_ids ──────────────────────────────────────────────────────


class TestExtractProductIds:
    def test_dedup_preserves_first_occurrence_order(self):
        rows = [
            {"product_id": 3},
            {"product_id": 1},
            {"product_id": 3},
            {"product_id": 2},
        ]
        assert _extract_product_ids(rows) == [3, 1, 2]

    def test_empty_input(self):
        assert _extract_product_ids([]) == []

    def test_none_product_id_skipped(self):
        rows = [{"product_id": None}, {"product_id": 5}, {"product_id": None}]
        assert _extract_product_ids(rows) == [5]

    def test_string_product_id_coerced(self):
        rows = [{"product_id": "7"}, {"product_id": "7"}, {"product_id": "9"}]
        assert _extract_product_ids(rows) == [7, 9]


# ── _fake_predict ─────────────────────────────────────────────────────────────


class TestFakePredict:
    def test_returns_correct_count(self):
        assert len(_fake_predict(weeks_ahead=8)) == 8

    def test_all_keys_present(self):
        for row in _fake_predict(weeks_ahead=4):
            assert set(row.keys()) == {"week_start", "forecast_qty", "lower_bound", "upper_bound"}

    def test_bounds_straddle_forecast(self):
        for row in _fake_predict(weeks_ahead=4):
            assert row["lower_bound"] < row["forecast_qty"] < row["upper_bound"]

    def test_week_start_is_monday(self):
        for row in _fake_predict(weeks_ahead=4):
            d = date.fromisoformat(row["week_start"])
            assert d.weekday() == 0, f"{row['week_start']} is not a Monday"


# ── _next_mondays ─────────────────────────────────────────────────────────────


class TestNextMondays:
    def test_all_are_mondays(self):
        for s in _next_mondays(6):
            d = date.fromisoformat(s)
            assert d.weekday() == 0

    def test_count(self):
        assert len(_next_mondays(10)) == 10

    def test_ascending_order(self):
        result = _next_mondays(5)
        dates = [date.fromisoformat(s) for s in result]
        assert dates == sorted(dates)
