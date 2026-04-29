"""
erp_tools.py — Async tool callers that hit Fastify read endpoints.

All calls forward the user JWT so Fastify enforces role-based access.
Callers must handle httpx.HTTPStatusError for 403/404 cases.
"""

import os

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
