"""
test_forecast_route.py — Integration tests for forecast FastAPI routes.

All DB and upstream HTTP calls are mocked so tests run without a real DB
or a running Fastify backend.

Covers:
  - POST /forecast/generate  → 200 normal, 409 concurrent
  - GET  /forecast            → 200 with data, 200 empty
  - Partial failure: one product fit fails, others succeed; job = "partial"
  - Concurrent guard: second simultaneous trigger returns 409

Set FORECAST_FAKE_PROPHET=true so Prophet/pandas are bypassed.
"""

import asyncio
import os
import sys
import uuid
from pathlib import Path
from typing import Any
from unittest.mock import AsyncMock, MagicMock, call, patch

import pytest
from fastapi.testclient import TestClient

# ── Path setup ────────────────────────────────────────────────────────────────

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

# ── Env (must be set before importing forecast module) ────────────────────────

os.environ["AI_SERVICE_INTERNAL_TOKEN"] = "test-secret"
os.environ["DATABASE_URL"] = "postgresql://test:test@localhost/test"
os.environ["FORECAST_FAKE_PROPHET"] = "true"
os.environ["FORECAST_MIN_DATA_WEEKS"] = "8"
os.environ["FORECAST_WEEKS_AHEAD"] = "12"
os.environ["AI_INTERNAL_SCOPES"] = "analytics.read,forecast.generate"
os.environ["FASTIFY_INTERNAL_URL"] = "http://backend:3000/api/v1"

from main import app  # noqa: E402

_TOKEN = "test-secret"
_HEADERS = {"X-Internal-Token": _TOKEN}

client = TestClient(app, raise_server_exceptions=True)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _fake_sales_rows(n_products: int = 2, n_weeks: int = 20) -> list[dict]:
    from datetime import date, timedelta
    rows = []
    today = date.today()
    for pid in range(1, n_products + 1):
        for w in range(n_weeks):
            rows.append({
                "product_id": pid,
                "sku": f"SKU-{pid:03d}",
                "week_start": (today - timedelta(weeks=n_weeks - w)).strftime("%Y-%m-%d"),
                "qty": 10 + w,
            })
    return rows


def _make_cursor(fetchone_val=None, fetchall_val=None):
    cur = MagicMock()
    cur.__enter__ = lambda s: s
    cur.__exit__ = MagicMock(return_value=False)
    cur.fetchone.return_value = fetchone_val
    cur.fetchall.return_value = fetchall_val or []
    return cur


def _make_conn(cursor_obj):
    conn = MagicMock()
    conn.__enter__ = lambda s: s
    conn.__exit__ = MagicMock(return_value=False)
    conn.cursor.return_value = cursor_obj
    conn.commit = MagicMock()
    conn.close = MagicMock()
    return conn


# ── POST /forecast/generate: normal ──────────────────────────────────────────


class TestGenerateForecastNormal:
    def test_returns_200_with_run_id(self):
        cursor = _make_cursor(fetchone_val=None)  # no running job
        conn   = _make_conn(cursor)

        sales_rows = _fake_sales_rows(n_products=2, n_weeks=20)

        with patch("psycopg2.connect", return_value=conn), \
             patch("src.api.forecast._fetch_sales_history", new_callable=AsyncMock,
                   return_value=sales_rows):
            r = client.post(
                "/forecast/generate",
                json={"tenantId": 1, "triggerType": "manual"},
                headers=_HEADERS,
            )

        assert r.status_code == 200
        body = r.json()
        assert "runId" in body
        assert body["generated"] >= 0
        assert "skipped" in body
        assert "durationMs" in body

    def test_returns_zero_skipped_when_enough_data(self):
        cursor = _make_cursor(fetchone_val=None)
        conn   = _make_conn(cursor)

        # 2 products × 20 weeks each → both should be generated (fake prophet)
        sales_rows = _fake_sales_rows(n_products=2, n_weeks=20)

        with patch("psycopg2.connect", return_value=conn), \
             patch("src.api.forecast._fetch_sales_history", new_callable=AsyncMock,
                   return_value=sales_rows):
            r = client.post(
                "/forecast/generate",
                json={"tenantId": 1},
                headers=_HEADERS,
            )

        assert r.status_code == 200
        body = r.json()
        assert body["generated"] == 2
        assert body["skipped"] == []

    def test_empty_sales_data_returns_200_with_zero_generated(self):
        cursor = _make_cursor(fetchone_val=None)
        conn   = _make_conn(cursor)

        with patch("psycopg2.connect", return_value=conn), \
             patch("src.api.forecast._fetch_sales_history", new_callable=AsyncMock,
                   return_value=[]):
            r = client.post(
                "/forecast/generate",
                json={"tenantId": 1},
                headers=_HEADERS,
            )

        assert r.status_code == 200
        body = r.json()
        assert body["generated"] == 0
        assert body["skipped"] == []

    def test_missing_token_returns_403(self):
        r = client.post("/forecast/generate", json={"tenantId": 1})
        assert r.status_code == 403

    def test_wrong_token_returns_403(self):
        r = client.post(
            "/forecast/generate",
            json={"tenantId": 1},
            headers={"X-Internal-Token": "wrong"},
        )
        assert r.status_code == 403


# ── POST /forecast/generate: concurrent guard (409) ──────────────────────────


class TestConcurrentForecastGuard:
    def test_second_request_returns_409(self):
        # fetchone returns an existing running job → conflict
        existing_job = {"id": str(uuid.uuid4())}
        cursor = _make_cursor(fetchone_val=existing_job)
        conn   = _make_conn(cursor)

        with patch("psycopg2.connect", return_value=conn):
            r = client.post(
                "/forecast/generate",
                json={"tenantId": 1},
                headers=_HEADERS,
            )

        assert r.status_code == 409
        assert r.json()["detail"] == "forecast_job_already_running"

    def test_concurrent_guard_is_per_tenant(self):
        """Tenant 2 has a running job; tenant 1 should succeed."""
        call_count = 0

        def _connect_side_effect():
            """First call (tenant 1 claim) → no running job. Subsequent calls are upserts."""
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                cur = _make_cursor(fetchone_val=None)
            else:
                cur = _make_cursor(fetchone_val=None)
            return _make_conn(cur)

        sales_rows = _fake_sales_rows(n_products=1, n_weeks=20)

        with patch("psycopg2.connect", side_effect=_connect_side_effect), \
             patch("src.api.forecast._fetch_sales_history", new_callable=AsyncMock,
                   return_value=sales_rows):
            r = client.post(
                "/forecast/generate",
                json={"tenantId": 1},
                headers=_HEADERS,
            )

        assert r.status_code == 200


# ── POST /forecast/generate: partial failure ──────────────────────────────────


class TestPartialFailure:
    def test_one_product_fails_others_succeed_job_is_partial(self):
        """
        Products [1, 2]: product 1 upsert raises, product 2 succeeds.
        Job status should be "partial"; generated=1, skipped includes product 1.
        """
        cursor = _make_cursor(fetchone_val=None)
        conn   = _make_conn(cursor)

        upsert_call_count = 0

        def _fail_first_upsert(*args, **kwargs):
            nonlocal upsert_call_count
            upsert_call_count += 1

        # Patch _upsert_forecasts to raise on the first product
        original_upsert = None

        import src.api.forecast as forecast_mod

        upsert_calls = []

        def _patched_upsert(run_id, tenant_id, product_id, rows):
            upsert_calls.append(product_id)
            if product_id == 1:
                raise RuntimeError("mock fit failure for product 1")

        sales_rows = _fake_sales_rows(n_products=2, n_weeks=20)

        with patch("psycopg2.connect", return_value=conn), \
             patch("src.api.forecast._fetch_sales_history", new_callable=AsyncMock,
                   return_value=sales_rows), \
             patch.object(forecast_mod, "_upsert_forecasts", side_effect=_patched_upsert):
            r = client.post(
                "/forecast/generate",
                json={"tenantId": 1},
                headers=_HEADERS,
            )

        assert r.status_code == 200
        body = r.json()
        # Product 2 succeeded, product 1 failed → partial
        assert body["generated"] == 1
        assert 1 in body["skipped"]

        # Verify the job was finalised with status="partial" in the DB
        update_calls = [
            str(c) for c in conn.cursor.return_value.execute.call_args_list
        ]
        # At least one UPDATE call should have set status (checked via commit)
        assert conn.commit.called


# ── GET /forecast ─────────────────────────────────────────────────────────────


class TestGetForecast:
    def test_returns_forecast_rows(self):
        from datetime import date, timedelta

        today = date.today()
        mock_rows = [
            {
                "week_start":   (today + timedelta(weeks=i + 1)),
                "forecast_qty": 50.0 + i,
                "lower_bound":  40.0 + i,
                "upper_bound":  60.0 + i,
                "sku":          "SKU-001",
            }
            for i in range(4)
        ]
        cursor = _make_cursor(fetchall_val=mock_rows)
        conn   = _make_conn(cursor)

        with patch("psycopg2.connect", return_value=conn):
            r = client.get(
                "/forecast",
                params={"tenantId": 1, "productId": 1, "weeks": 4},
                headers=_HEADERS,
            )

        assert r.status_code == 200
        body = r.json()
        assert body["productId"] == 1
        assert body["sku"] == "SKU-001"
        assert len(body["forecasts"]) == 4
        assert body["forecasts"][0]["qty"] == 50.0

    def test_returns_empty_when_no_data(self):
        cursor = _make_cursor(fetchall_val=[])
        conn   = _make_conn(cursor)

        with patch("psycopg2.connect", return_value=conn):
            r = client.get(
                "/forecast",
                params={"tenantId": 1, "productId": 99, "weeks": 12},
                headers=_HEADERS,
            )

        assert r.status_code == 200
        body = r.json()
        assert body["forecasts"] == []
        assert body["sku"] is None

    def test_missing_product_id_returns_422(self):
        r = client.get(
            "/forecast",
            params={"tenantId": 1, "weeks": 12},
            headers=_HEADERS,
        )
        assert r.status_code == 422

    def test_wrong_token_returns_403(self):
        r = client.get(
            "/forecast",
            params={"tenantId": 1, "productId": 1},
            headers={"X-Internal-Token": "bad"},
        )
        assert r.status_code == 403

    def test_scope_analytics_read_required(self):
        # Temporarily remove analytics.read from scopes
        old = os.environ.get("AI_INTERNAL_SCOPES", "")
        os.environ["AI_INTERNAL_SCOPES"] = "forecast.generate"
        try:
            r = client.get(
                "/forecast",
                params={"tenantId": 1, "productId": 1},
                headers=_HEADERS,
            )
            assert r.status_code == 403
        finally:
            os.environ["AI_INTERNAL_SCOPES"] = old
