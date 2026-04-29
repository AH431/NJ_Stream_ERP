import asyncio
import json
import os

import httpx
from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from src.tools.query_parser import parse_question
from src.tools.erp_tools import search_products, get_inventory
from src.tools.formatters import (
    format_inventory_answer,
    format_not_found,
    format_api_error,
    format_blocked_response,
)

INTERNAL_TOKEN = os.environ.get("AI_SERVICE_INTERNAL_TOKEN", "")
FASTIFY_BASE_URL = os.environ.get("FASTIFY_BASE_URL", "http://localhost:3000/api/v1")

# Fallback tokens used when query route is static (RAG not yet implemented)
_STATIC_PLACEHOLDER = [
    "此問題需要知識庫回答，", "RAG 模組將於", "PR-6 啟用。",
]

router = APIRouter()


class ChatRequest(BaseModel):
    question: str
    userJwt: str
    role: str
    userId: int
    requestId: str


async def _token_stream(tokens: list[str], delay: float = 0.05):
    for token in tokens:
        yield f'data: {json.dumps({"type": "token", "content": token})}\n\n'
        await asyncio.sleep(delay)
    yield f'data: {json.dumps({"type": "done"})}\n\n'


async def _text_stream(text: str):
    chunk_size = 20
    for i in range(0, len(text), chunk_size):
        yield f'data: {json.dumps({"type": "token", "content": text[i:i + chunk_size]})}\n\n'
        await asyncio.sleep(0.02)
    yield f'data: {json.dumps({"type": "done"})}\n\n'


async def _resolve_inventory(jwt: str, sku: str) -> str:
    try:
        search_result = await search_products(jwt, sku, FASTIFY_BASE_URL)
        items = search_result.get("items", [])
        if not items:
            return format_not_found(sku)
        product = items[0]
        inventory = await get_inventory(jwt, product["id"], FASTIFY_BASE_URL)
        return format_inventory_answer(product, inventory)
    except httpx.HTTPStatusError as e:
        return format_api_error(e.response.status_code)
    except Exception:
        return format_api_error(503)


def _sse_response(generator) -> StreamingResponse:
    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.post("/chat")
async def chat(
    body: ChatRequest,
    x_internal_token: str = Header(...),
):
    if not INTERNAL_TOKEN or x_internal_token != INTERNAL_TOKEN:
        raise HTTPException(status_code=403, detail="forbidden")

    parsed = parse_question(body.question)

    if parsed.route == "blocked":
        return _sse_response(_text_stream(format_blocked_response()))

    if parsed.route == "dynamic" and parsed.tool == "inventory" and parsed.sku:
        answer = await _resolve_inventory(body.userJwt, parsed.sku)
        return _sse_response(_text_stream(answer))

    # static or unhandled dynamic → placeholder until PR-6/PR-7
    return _sse_response(_token_stream(_STATIC_PLACEHOLDER))
