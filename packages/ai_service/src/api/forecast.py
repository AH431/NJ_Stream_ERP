"""
forecast.py — Demand forecasting endpoints.

POST /forecast/generate  scope: forecast.generate
GET  /forecast           scope: analytics.read

DB access is via psycopg2 (sync, run in asyncio.to_thread).
Set FORECAST_FAKE_PROPHET=true to skip Prophet/pandas for local dev on Windows.
"""

import asyncio
import os
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Optional

import httpx
import psycopg2
import psycopg2.extras
from fastapi import APIRouter, Header, HTTPException, Query
from pydantic import BaseModel

from src.utils.db import db_connect
from src.utils.logger import get_logger

_log = get_logger("forecast")

router = APIRouter()

# ── Environment ────────────────────────────────────────────────────────────────
_INTERNAL_TOKEN = os.environ.get("AI_SERVICE_INTERNAL_TOKEN", "")
_FASTIFY_BASE_URL = os.environ.get("FASTIFY_INTERNAL_URL", "http://localhost:3000/api/v1")
_DATABASE_URL = os.environ.get("DATABASE_URL", "")
_FORECAST_WEEKS_AHEAD = int(os.environ.get("FORECAST_WEEKS_AHEAD", "12"))
_FORECAST_MIN_DATA_WEEKS = int(os.environ.get("FORECAST_MIN_DATA_WEEKS", "8"))
_FORECAST_JOB_LEASE_SECONDS = int(os.environ.get("FORECAST_JOB_LEASE_SECONDS", "900"))
_FORECAST_FAKE_PROPHET = os.environ.get("FORECAST_FAKE_PROPHET", "false").lower() == "true"
_MODEL_VERSION = "prophet-v1"


# ── Auth ───────────────────────────────────────────────────────────────────────

def _allowed_scopes() -> set[str]:
    raw = os.environ.get("AI_INTERNAL_SCOPES", "analytics.read,forecast.generate")
    return {s.strip() for s in raw.split(",") if s.strip()}


def _verify(token: str, required_scope: str) -> None:
    if not _INTERNAL_TOKEN or token != _INTERNAL_TOKEN:
        raise HTTPException(status_code=403, detail="forbidden")
    if required_scope not in _allowed_scopes():
        raise HTTPException(status_code=403, detail=f"scope '{required_scope}' not configured")


# ── DB helpers (all sync — call via asyncio.to_thread) ─────────────────────────

def _claim_job(
    tenant_id: int,
    weeks_ahead: int,
    trigger_type: str,
    requested_by: Optional[int],
) -> str:
    """
    Insert a forecast_jobs row with status='running'.
    Raises RuntimeError("forecast_job_already_running") if a live lease exists.
    Returns the new job UUID.
    """
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            # Serialize concurrent claims for the same tenant so that the
            # SELECT + INSERT below is effectively atomic.
            cur.execute("SELECT pg_advisory_xact_lock(%s)", (tenant_id,))

            cur.execute(
                """
                SELECT id FROM forecast_jobs
                WHERE tenant_id = %s
                  AND status = 'running'
                  AND lease_expires_at > NOW()
                LIMIT 1
                """,
                (tenant_id,),
            )
            if cur.fetchone():
                raise RuntimeError("forecast_job_already_running")

            run_id = str(uuid.uuid4())
            lease_expires = datetime.now(timezone.utc) + timedelta(seconds=_FORECAST_JOB_LEASE_SECONDS)
            cur.execute(
                """
                INSERT INTO forecast_jobs
                  (id, tenant_id, requested_by, trigger_type, status,
                   weeks_ahead, model_version, started_at, lease_expires_at)
                VALUES (%s, %s, %s, %s, 'running', %s, %s, NOW(), %s)
                """,
                (run_id, tenant_id, requested_by, trigger_type,
                 weeks_ahead, _MODEL_VERSION, lease_expires),
            )
        conn.commit()
        return run_id
    finally:
        conn.close()


def _finish_job(
    run_id: str,
    status: str,
    generated_cnt: int,
    skipped_cnt: int,
    error_summary: Optional[str],
) -> None:
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE forecast_jobs
                SET status        = %s,
                    finished_at   = NOW(),
                    generated_cnt = %s,
                    skipped_cnt   = %s,
                    error_summary = %s
                WHERE id = %s
                """,
                (status, generated_cnt, skipped_cnt, error_summary, run_id),
            )
        conn.commit()
    finally:
        conn.close()


def _upsert_forecasts(
    run_id: str,
    tenant_id: int,
    product_id: int,
    rows: list[dict],
) -> None:
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            for r in rows:
                cur.execute(
                    """
                    INSERT INTO demand_forecasts
                      (product_id, tenant_id, week_start, forecast_qty,
                       lower_bound, upper_bound, model_version, run_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (tenant_id, product_id, week_start, model_version)
                    DO UPDATE SET
                      forecast_qty = EXCLUDED.forecast_qty,
                      lower_bound  = EXCLUDED.lower_bound,
                      upper_bound  = EXCLUDED.upper_bound,
                      run_id       = EXCLUDED.run_id,
                      generated_at = NOW()
                    """,
                    (
                        product_id, tenant_id,
                        r["week_start"], r["forecast_qty"],
                        r["lower_bound"], r["upper_bound"],
                        _MODEL_VERSION, run_id,
                    ),
                )
        conn.commit()
    finally:
        conn.close()


def _query_forecasts(tenant_id: int, product_id: int, weeks: int) -> list:
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT df.week_start,
                       df.forecast_qty,
                       df.lower_bound,
                       df.upper_bound,
                       p.sku
                FROM demand_forecasts df
                JOIN products p ON p.id = df.product_id
                WHERE df.tenant_id  = %s
                  AND df.product_id = %s
                  AND df.week_start >= CURRENT_DATE
                ORDER BY df.week_start
                LIMIT %s
                """,
                (tenant_id, product_id, weeks),
            )
            return cur.fetchall()
    finally:
        conn.close()


# ── HTTP helper ────────────────────────────────────────────────────────────────

async def _fetch_sales_history(tenant_id: int, weeks: int) -> list[dict]:
    """
    GET /api/v1/analytics/sales-history (internal endpoint, M3.3).
    Expected response: list of {product_id, sku, week_start, qty}.
    """
    url = f"{_FASTIFY_BASE_URL}/analytics/sales-history"
    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.get(
            url,
            params={"tenantId": tenant_id, "weeks": weeks},
            headers={"X-Internal-Token": _INTERNAL_TOKEN},
        )
        r.raise_for_status()
        data = r.json()
        return data if isinstance(data, list) else data.get("items", [])


# ── Prediction helpers ─────────────────────────────────────────────────────────

def _next_mondays(n: int) -> list[str]:
    today = date.today()
    days_until_monday = (7 - today.weekday()) % 7 or 7
    start = today + timedelta(days=days_until_monday)
    return [(start + timedelta(weeks=i)).strftime("%Y-%m-%d") for i in range(n)]


def _fake_predict(weeks_ahead: int) -> list[dict]:
    import random
    result = []
    for w in _next_mondays(weeks_ahead):
        qty = round(random.uniform(10.0, 100.0), 2)
        result.append({
            "week_start":   w,
            "forecast_qty": qty,
            "lower_bound":  round(qty * 0.8, 2),
            "upper_bound":  round(qty * 1.2, 2),
        })
    return result


def _prophet_predict(df_product, weeks_ahead: int) -> Optional[list[dict]]:
    """
    Fit Prophet on weekly sales data for one product.
    Returns None when row count < _FORECAST_MIN_DATA_WEEKS (mark as skipped).
    Caller must run this in asyncio.to_thread — Prophet.fit() is CPU-bound.
    """
    if len(df_product) < _FORECAST_MIN_DATA_WEEKS:
        return None

    import pandas as pd
    from prophet import Prophet

    train = (
        df_product[["week_start", "qty"]]
        .rename(columns={"week_start": "ds", "qty": "y"})
        .copy()
    )
    train["ds"] = pd.to_datetime(train["ds"])
    train = train.dropna(subset=["y"])

    m = Prophet(weekly_seasonality=False, daily_seasonality=False, yearly_seasonality=True)
    m.fit(train)

    future = m.make_future_dataframe(periods=weeks_ahead, freq="W-MON")
    forecast = m.predict(future)
    last_known = train["ds"].max()
    future_only = forecast[forecast["ds"] > last_known].head(weeks_ahead)

    return [
        {
            "week_start":   row["ds"].strftime("%Y-%m-%d"),
            "forecast_qty": max(0.0, round(float(row["yhat"]),       2)),
            "lower_bound":  max(0.0, round(float(row["yhat_lower"]), 2)),
            "upper_bound":  round(float(row["yhat_upper"]), 2),
        }
        for _, row in future_only.iterrows()
    ]


def _extract_product_ids(sales_rows: list[dict]) -> list[int]:
    seen: set[int] = set()
    result: list[int] = []
    for row in sales_rows:
        pid = row.get("product_id")
        if pid is not None:
            pid = int(pid)
            if pid not in seen:
                seen.add(pid)
                result.append(pid)
    return result


def _ms(t0: float) -> int:
    return round((time.monotonic() - t0) * 1000)


# ── Request model ──────────────────────────────────────────────────────────────

class GenerateRequest(BaseModel):
    tenantId: int
    productIds: Optional[list[int]] = None
    weeksAhead: Optional[int] = None
    triggerType: Optional[str] = "manual"
    requestedBy: Optional[int] = None


# ── Routes ─────────────────────────────────────────────────────────────────────

@router.post("/forecast/generate")
async def generate_forecast(
    body: GenerateRequest,
    x_internal_token: str = Header(...),
):
    _verify(x_internal_token, "forecast.generate")

    t0 = time.monotonic()
    tenant_id   = body.tenantId
    weeks_ahead = body.weeksAhead or _FORECAST_WEEKS_AHEAD
    trigger     = body.triggerType or "manual"

    _log.info("forecast.start", extra={
        "tenantId":    tenant_id,
        "triggerType": trigger,
        "weeksAhead":  weeks_ahead,
    })

    # ── 0. Claim job (blocks concurrent runs for same tenant) ──────────────────
    try:
        run_id = await asyncio.to_thread(_claim_job, tenant_id, weeks_ahead, trigger, body.requestedBy)
    except RuntimeError as e:
        msg = str(e)
        if "already_running" in msg:
            raise HTTPException(status_code=409, detail="forecast_job_already_running")
        _log.error("forecast.claim.error", extra={"tenantId": tenant_id, "error": msg})
        raise HTTPException(status_code=503, detail=msg)

    _log.info("forecast.job.claimed", extra={"jobId": run_id, "tenantId": tenant_id})

    generated = 0
    skipped:   list[int] = []
    errors:    list[str] = []

    try:
        # ── 1. Fetch weekly sales history from Fastify ─────────────────────────
        try:
            sales_rows = await _fetch_sales_history(tenant_id, 52)
        except httpx.HTTPStatusError as e:
            raise RuntimeError(f"sales_history_upstream_error:{e.response.status_code}")
        except httpx.TimeoutException:
            raise RuntimeError("sales_history_timeout")

        if not sales_rows:
            _log.warning("forecast.no_data", extra={"jobId": run_id, "tenantId": tenant_id})
            await asyncio.to_thread(_finish_job, run_id, "success", 0, 0, "no_sales_data")
            return {"runId": run_id, "generated": 0, "skipped": [], "durationMs": _ms(t0)}

        # ── 2. Determine product list ──────────────────────────────────────────
        product_ids: list[int] = body.productIds or _extract_product_ids(sales_rows)

        # Build a simple {product_id: [rows]} index (no pandas needed here)
        by_product: dict[int, list[dict]] = {}
        for row in sales_rows:
            pid = int(row["product_id"])
            by_product.setdefault(pid, []).append(row)

        # ── 3-5. Fit / predict / upsert per product ────────────────────────────
        for pid in product_ids:
            try:
                rows_for_pid = by_product.get(pid, [])

                if _FORECAST_FAKE_PROPHET:
                    forecasts = _fake_predict(weeks_ahead)
                else:
                    # Build minimal DataFrame only for Prophet
                    import pandas as pd
                    df_p = pd.DataFrame(rows_for_pid)
                    forecasts = await asyncio.to_thread(_prophet_predict, df_p, weeks_ahead)

                if forecasts is None:
                    _log.info("forecast.product.skipped", extra={
                        "jobId":    run_id,
                        "productId": pid,
                        "rows":     len(rows_for_pid),
                        "reason":   "insufficient_data",
                    })
                    skipped.append(pid)
                    continue

                await asyncio.to_thread(_upsert_forecasts, run_id, tenant_id, pid, forecasts)
                generated += 1
                _log.info("forecast.product.done", extra={
                    "jobId":     run_id,
                    "productId": pid,
                    "weeks":     len(forecasts),
                })

            except Exception as e:
                err = f"product_{pid}: {str(e)[:120]}"
                _log.error("forecast.product.error", extra={
                    "jobId":     run_id,
                    "productId": pid,
                    "error":     str(e),
                })
                errors.append(err)
                skipped.append(pid)

        # ── 6. Finalise job record ─────────────────────────────────────────────
        if errors and generated == 0:
            final_status = "failed"
        elif errors:
            final_status = "partial"
        else:
            final_status = "success"

        error_summary = "; ".join(errors) if errors else None
        await asyncio.to_thread(
            _finish_job, run_id, final_status, generated, len(skipped), error_summary
        )

        duration_ms = _ms(t0)
        _log.info("forecast.done", extra={
            "jobId":      run_id,
            "tenantId":   tenant_id,
            "generated":  generated,
            "skipped":    len(skipped),
            "durationMs": duration_ms,
            "status":     final_status,
        })
        return {
            "runId":       run_id,
            "generated":   generated,
            "skipped":     skipped,
            "durationMs":  duration_ms,
        }

    except Exception as e:
        err_msg = str(e)[:500]
        _log.error("forecast.error", extra={"jobId": run_id, "tenantId": tenant_id, "error": err_msg})
        await asyncio.to_thread(_finish_job, run_id, "failed", generated, len(skipped), err_msg)
        raise HTTPException(status_code=500, detail="forecast_generation_failed")


@router.get("/forecast")
async def get_forecast(
    tenantId:  int = Query(...),
    productId: int = Query(...),
    weeks:     int = Query(12),
    x_internal_token: str = Header(...),
):
    _verify(x_internal_token, "analytics.read")

    try:
        rows = await asyncio.to_thread(_query_forecasts, tenantId, productId, weeks)
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    if not rows:
        return {"productId": productId, "sku": None, "forecasts": []}

    return {
        "productId": productId,
        "sku":       rows[0]["sku"],
        "forecasts": [
            {
                "weekStart": str(r["week_start"]),
                "qty":       float(r["forecast_qty"]),
                "lower":     float(r["lower_bound"])  if r["lower_bound"]  is not None else None,
                "upper":     float(r["upper_bound"])  if r["upper_bound"]  is not None else None,
            }
            for r in rows
        ],
    }
