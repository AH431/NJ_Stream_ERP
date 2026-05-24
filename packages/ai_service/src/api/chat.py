import asyncio
import json
import os
import time

import httpx
from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from src.utils.logger import get_logger

_log = get_logger("chat")

from src.router.query_router import route as route_question
from src.tools.erp_tools import (
    get_demand_forecast,
    get_inventory,
    get_quotation,
    get_sales_order,
    search_customers,
    search_products,
)
from src.tools.formatters import (
    format_customer_search_answer,
    format_forecast_answer,
    format_forecast_not_found,
    format_inventory_answer,
    format_api_error,
    format_blocked_response,
    format_not_found,
    format_quotation_answer,
    format_sales_order_answer,
)

INTERNAL_TOKEN = os.environ.get("AI_SERVICE_INTERNAL_TOKEN", "")
FASTIFY_BASE_URL = os.environ.get("FASTIFY_INTERNAL_URL", "http://localhost:3000/api/v1")
AI_FAKE_LLM = os.environ.get("AI_FAKE_LLM", "false").lower() == "true"
CHROMA_PATH = os.environ.get("CHROMA_DB_PATH", "./db")

_rag_vs = None  # lazy-initialized Chroma vectorstore

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


async def _blocked_stream():
    yield f'data: {json.dumps({"type": "blocked"})}\n\n'
    async for chunk in _text_stream(format_blocked_response()):
        yield chunk


async def _resolve_inventory(jwt: str, sku: str, request_id: str = "") -> str:
    try:
        search_result = await search_products(jwt, sku, FASTIFY_BASE_URL)
        items = search_result.get("items", [])
        if not items:
            return format_not_found(sku)
        product = items[0]
        inventory = await get_inventory(jwt, product["id"], FASTIFY_BASE_URL)
        return format_inventory_answer(product, inventory)
    except httpx.HTTPStatusError as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_inventory", "statusCode": e.response.status_code})
        return format_api_error(e.response.status_code)
    except httpx.TimeoutException:
        _log.error("upstream.timeout", extra={"requestId": request_id, "tool": "get_inventory", "upstreamTimeout": True})
        return format_api_error(503)
    except Exception as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_inventory", "errorSummary": str(e)})
        return format_api_error(503)


async def _resolve_quotation(jwt: str, entity_id: int, request_id: str = "") -> str:
    try:
        quotation = await get_quotation(jwt, entity_id, FASTIFY_BASE_URL)
        return format_quotation_answer(quotation)
    except httpx.HTTPStatusError as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_quotation", "statusCode": e.response.status_code})
        return format_api_error(e.response.status_code)
    except httpx.TimeoutException:
        _log.error("upstream.timeout", extra={"requestId": request_id, "tool": "get_quotation", "upstreamTimeout": True})
        return format_api_error(503)
    except Exception as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_quotation", "errorSummary": str(e)})
        return format_api_error(503)


async def _resolve_order(jwt: str, entity_id: int, request_id: str = "") -> str:
    try:
        order = await get_sales_order(jwt, entity_id, FASTIFY_BASE_URL)
        return format_sales_order_answer(order)
    except httpx.HTTPStatusError as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_sales_order", "statusCode": e.response.status_code})
        return format_api_error(e.response.status_code)
    except httpx.TimeoutException:
        _log.error("upstream.timeout", extra={"requestId": request_id, "tool": "get_sales_order", "upstreamTimeout": True})
        return format_api_error(503)
    except Exception as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_sales_order", "errorSummary": str(e)})
        return format_api_error(503)


async def _resolve_forecast(sku: str, request_id: str = "") -> str:
    try:
        data = await get_demand_forecast(sku, tenant_id=1, weeks=12)
        if data is None:
            return format_forecast_not_found(sku)
        return format_forecast_answer(data)
    except RuntimeError as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_demand_forecast", "errorSummary": str(e)})
        return format_api_error(503)
    except Exception as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "get_demand_forecast", "errorSummary": str(e)})
        return format_api_error(503)


async def _resolve_customer(jwt: str, search_term: str, request_id: str = "") -> str:
    try:
        result = await search_customers(jwt, search_term, FASTIFY_BASE_URL)
        return format_customer_search_answer(result.get("items", []), search_term)
    except httpx.HTTPStatusError as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "search_customers", "statusCode": e.response.status_code})
        return format_api_error(e.response.status_code)
    except httpx.TimeoutException:
        _log.error("upstream.timeout", extra={"requestId": request_id, "tool": "search_customers", "upstreamTimeout": True})
        return format_api_error(503)
    except Exception as e:
        _log.error("upstream.error", extra={"requestId": request_id, "tool": "search_customers", "errorSummary": str(e)})
        return format_api_error(503)


def _ms(t0: float) -> int:
    return round((time.monotonic() - t0) * 1000)


def _sse_response(generator) -> StreamingResponse:
    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


def _get_rag_vectorstore():
    global _rag_vs
    if _rag_vs is None:
        from src.indexing.embedder import get_embeddings
        from src.indexing.vectorstore import get_vectorstore
        _rag_vs = get_vectorstore(get_embeddings(), db_path=CHROMA_PATH)
    return _rag_vs


async def _tool_answer_stream(tool: str, resource_type: str, resource_id, answer: str):
    payload = {
        "type": "tool_call",
        "tool": tool,
        "resourceType": resource_type,
        "resourceId": resource_id,
    }
    yield f'data: {json.dumps(payload)}\n\n'
    async for chunk in _text_stream(answer):
        yield chunk


async def _rag_stream(question: str, role: str):
    from src.rag.retriever import build_hybrid_retriever
    from src.rag.prompt import RAG_PROMPT

    try:
        vs = _get_rag_vectorstore()
        retriever = build_hybrid_retriever(vs, role=role)
        docs = await asyncio.to_thread(retriever.invoke, question)
    except Exception:
        yield f'data: {json.dumps({"type": "token", "content": "知識庫暫時無法存取，請稍後再試。"})}\n\n'
        yield f'data: {json.dumps({"type": "done"})}\n\n'
        return

    if not docs:
        yield f'data: {json.dumps({"type": "token", "content": "根據現有資料，無法回答此問題。"})}\n\n'
        yield f'data: {json.dumps({"type": "done"})}\n\n'
        return

    context = "\n\n".join(d.page_content for d in docs)

    if AI_FAKE_LLM:
        async for chunk in _text_stream(context[:300]):
            yield chunk
        return

    from langchain_ollama import ChatOllama
    model = ChatOllama(
        base_url=os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434"),
        model=os.environ.get("OLLAMA_MODEL", "llama3.2:3b"),
        num_ctx=int(os.environ.get("OLLAMA_NUM_CTX", "8192")),
        temperature=float(os.environ.get("OLLAMA_TEMPERATURE", "0.3")),
    )
    prompt_msgs = RAG_PROMPT.format_messages(context=context, question=question)
    async for chunk in model.astream(prompt_msgs):
        content = chunk.content if hasattr(chunk, "content") else ""
        if content:
            yield f'data: {json.dumps({"type": "token", "content": content})}\n\n'
    yield f'data: {json.dumps({"type": "done"})}\n\n'


@router.post("/chat")
async def chat(
    body: ChatRequest,
    x_internal_token: str = Header(...),
):
    if not INTERNAL_TOKEN or x_internal_token != INTERNAL_TOKEN:
        _log.warning("chat.forbidden", extra={"requestId": body.requestId, "userId": body.userId})
        raise HTTPException(status_code=403, detail="forbidden")

    t0 = time.monotonic()
    model_name = os.environ.get("OLLAMA_MODEL", "llama3.2:3b")
    _log.info("chat.start", extra={"requestId": body.requestId, "userId": body.userId, "model": model_name})

    parsed = route_question(body.question)

    if parsed.route == "blocked":
        _log.info("chat.blocked", extra={"requestId": body.requestId, "durationMs": _ms(t0)})
        return _sse_response(_blocked_stream())

    if parsed.route == "dynamic" and parsed.tool == "inventory" and parsed.sku:
        answer = await _resolve_inventory(body.userJwt, parsed.sku, body.requestId)
        _log.info("chat.done", extra={"requestId": body.requestId, "tool": "get_inventory", "model": model_name, "durationMs": _ms(t0)})
        return _sse_response(_tool_answer_stream("get_inventory", "inventory", parsed.sku, answer))

    if parsed.route == "dynamic" and parsed.tool == "quotation" and parsed.entity_id:
        answer = await _resolve_quotation(body.userJwt, parsed.entity_id, body.requestId)
        _log.info("chat.done", extra={"requestId": body.requestId, "tool": "get_quotation", "model": model_name, "durationMs": _ms(t0)})
        return _sse_response(_tool_answer_stream("get_quotation", "quotation", parsed.entity_id, answer))

    if parsed.route == "dynamic" and parsed.tool == "order" and parsed.entity_id:
        answer = await _resolve_order(body.userJwt, parsed.entity_id, body.requestId)
        _log.info("chat.done", extra={"requestId": body.requestId, "tool": "get_sales_order", "model": model_name, "durationMs": _ms(t0)})
        return _sse_response(_tool_answer_stream("get_sales_order", "sales_order", parsed.entity_id, answer))

    if parsed.route == "dynamic" and parsed.tool == "customer" and parsed.search_term:
        answer = await _resolve_customer(body.userJwt, parsed.search_term, body.requestId)
        _log.info("chat.done", extra={"requestId": body.requestId, "tool": "search_customers", "model": model_name, "durationMs": _ms(t0)})
        return _sse_response(_tool_answer_stream("search_customers", "customer", None, answer))

    if parsed.route == "dynamic" and parsed.tool == "forecast" and parsed.sku:
        answer = await _resolve_forecast(parsed.sku, body.requestId)
        _log.info("chat.done", extra={"requestId": body.requestId, "tool": "get_demand_forecast", "model": model_name, "durationMs": _ms(t0)})
        return _sse_response(_tool_answer_stream("get_demand_forecast", "forecast", parsed.sku, answer))

    # static (or unhandled dynamic) → RAG pipeline (PR-6)
    _log.info("chat.done", extra={"requestId": body.requestId, "tool": "rag", "model": model_name, "durationMs": _ms(t0)})
    return _sse_response(_rag_stream(body.question, body.role))
