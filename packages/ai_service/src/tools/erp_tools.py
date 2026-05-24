"""
erp_tools.py — Async tool callers that hit Fastify read endpoints.

All calls forward the user JWT so Fastify enforces role-based access.
Callers must handle httpx.HTTPStatusError for 403/404 cases.

get_demand_forecast queries demand_forecasts directly via psycopg2 (no JWT needed).
"""

import asyncio
import os
from typing import Optional

import httpx

_DEFAULT_BASE_URL = os.environ.get("FASTIFY_INTERNAL_URL", "http://localhost:3000/api/v1")
_TIMEOUT = float(os.environ.get("ERP_TOOL_TIMEOUT", "10"))


def _auth_headers(jwt: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {jwt}"}


async def search_products(jwt: str, q: str, base_url: str = _DEFAULT_BASE_URL) -> dict:
    """GET /api/v1/products/search?q=<q>  → {"items": [...], "total": N}"""
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        r = await client.get(
            f"{base_url}/products/search",
            params={"q": q},
            headers=_auth_headers(jwt),
        )
        r.raise_for_status()
        return r.json()


async def get_inventory(jwt: str, product_id: int, base_url: str = _DEFAULT_BASE_URL) -> dict:
    """GET /api/v1/inventory?productId=<id>  → inventory record with availableQuantity"""
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        r = await client.get(
            f"{base_url}/inventory",
            params={"productId": product_id},
            headers=_auth_headers(jwt),
        )
        r.raise_for_status()
        return r.json()


async def search_customers(jwt: str, q: str, base_url: str = _DEFAULT_BASE_URL) -> dict:
    """GET /api/v1/customers/search?q=<q>  → {"items": [...], "total": N}"""
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        r = await client.get(
            f"{base_url}/customers/search",
            params={"q": q},
            headers=_auth_headers(jwt),
        )
        r.raise_for_status()
        return r.json()


async def get_quotation(jwt: str, quotation_id: int, base_url: str = _DEFAULT_BASE_URL) -> dict:
    """GET /api/v1/quotations/<id> → quotation header + items"""
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        r = await client.get(
            f"{base_url}/quotations/{quotation_id}",
            headers=_auth_headers(jwt),
        )
        r.raise_for_status()
        return r.json()


async def get_sales_order(jwt: str, order_id: int, base_url: str = _DEFAULT_BASE_URL) -> dict:
    """GET /api/v1/sales-orders/<id> → sales order header + items"""
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        r = await client.get(
            f"{base_url}/sales-orders/{order_id}",
            headers=_auth_headers(jwt),
        )
        r.raise_for_status()
        return r.json()


# ── Forecast tool (psycopg2 direct — no JWT required) ─────────────────────────

def _query_demand_forecast_sync(sku: str, tenant_id: int, weeks: int) -> Optional[dict]:
    """
    Returns {sku, product_id, current_stock, forecasts: [{week_start, qty, lower, upper}],
             reorder_alert, stockout_week} or None when no product found.
    """
    from src.utils.db import db_connect  # local import keeps module-level deps clean

    conn = db_connect()
    try:
        with conn.cursor() as cur:
            # Resolve product_id from SKU (case-insensitive)
            cur.execute(
                "SELECT id, name FROM products WHERE UPPER(sku) = UPPER(%s) AND deleted_at IS NULL LIMIT 1",
                (sku,),
            )
            product = cur.fetchone()
            if not product:
                return None

            product_id = product["id"]

            # Current available stock
            cur.execute(
                """
                SELECT COALESCE(quantity_on_hand - quantity_reserved, 0)::int AS available
                FROM inventory_items
                WHERE product_id = %s
                LIMIT 1
                """,
                (product_id,),
            )
            inv_row = cur.fetchone()
            current_stock = int(inv_row["available"]) if inv_row else 0

            # Demand forecasts (nearest `weeks` future weeks)
            cur.execute(
                """
                SELECT week_start::text, forecast_qty, lower_bound, upper_bound
                FROM demand_forecasts
                WHERE tenant_id = %s
                  AND product_id = %s
                  AND week_start >= CURRENT_DATE
                ORDER BY week_start
                LIMIT %s
                """,
                (tenant_id, product_id, weeks),
            )
            rows = cur.fetchall()

        forecasts = [
            {
                "week_start": r["week_start"],
                "qty": float(r["forecast_qty"]),
                "lower": float(r["lower_bound"]) if r["lower_bound"] is not None else None,
                "upper": float(r["upper_bound"]) if r["upper_bound"] is not None else None,
            }
            for r in rows
        ]

        total_forecast = sum(f["qty"] for f in forecasts)
        reorder_alert = total_forecast > current_stock if forecasts else False

        # Find first week where cumulative demand exceeds current stock
        stockout_week: Optional[str] = None
        cumulative = 0.0
        for f in forecasts:
            cumulative += f["qty"]
            if cumulative >= current_stock and current_stock >= 0:
                stockout_week = f["week_start"]
                break

        return {
            "sku":           sku.upper(),
            "product_id":    product_id,
            "current_stock": current_stock,
            "forecasts":     forecasts,
            "reorder_alert": reorder_alert,
            "stockout_week": stockout_week,
        }
    finally:
        conn.close()


async def get_demand_forecast(sku: str, tenant_id: int = 1, weeks: int = 4) -> Optional[dict]:
    """Async wrapper — runs psycopg2 query in a thread pool."""
    return await asyncio.to_thread(_query_demand_forecast_sync, sku, tenant_id, weeks)
