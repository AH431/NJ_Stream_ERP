"""
query_parser.py — Classify user questions into static / dynamic / blocked.

Blocked detection must achieve 100% precision (no LLM leakage).
Dynamic detection covers inventory, order, and quotation intent.
Everything else falls back to static (RAG).
"""

import re
from dataclasses import dataclass
from typing import Literal, Optional

# ── Patterns ──────────────────────────────────────────────────────────────────

# SKU: 2+ uppercase letters, hyphen, 1+ digits  (e.g. IC-8800, NJ-1001, CB-2200)
SKU_PATTERN = re.compile(r'\b([A-Z]{2,}-\d+)\b')

# Numeric entity ID: #42, ＃42, or "訂單/報價/order/quotation 42"
NUMERIC_ID_PATTERN = re.compile(
    r'[#＃](\d+)'
    r'|(?:訂單|報價單|報價|order|quotation)\s*[#＃]?\s*(\d+)',
    re.IGNORECASE,
)

_BLOCKED = [re.compile(p, re.IGNORECASE) for p in [
    r'SELECT\s+.+\s+FROM',
    r'\b(INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|DROP\s+TABLE)\b',
    r'忽略之前|ignore\s+previous|forget\s+(all\s+)?previous',
    r'system\s*prompt|提示詞',
    r'\bDAN\b|do\s+anything\s+now',
    r'沒有任何限制|without\s+any\s+restriction',
    r'假裝你是|pretend\s+you\s+are',
    r'debug\s*模式|debug\s+mode',
    r'API\s*[Tt]oken|內部\s*URL|internal\s+url',
    r'偽造|不要.{0,10}記錄',
    r'(資料庫|database)\s*(dump|傾印)',
    r'輸出.{0,10}上一個使用者',
    r'你.{0,5}(密碼|password)',
]]

_INVENTORY_DYNAMIC = [re.compile(p, re.IGNORECASE) for p in [
    r'現在.{0,20}庫存|庫存.{0,20}(現在|目前|剩|還有)',
    r'可用庫存|即時庫存|庫存狀況|存貨',
    r'庫存.{0,15}(多少|幾個|幾件|幾箱|幾套)',
    r'(現在|目前|即時).{0,10}(庫存|存貨)',
    r'低於.{0,15}(安全|水位)|安全水位',
]]

# ── Output type ───────────────────────────────────────────────────────────────

@dataclass
class ParsedQuery:
    route: Literal['static', 'dynamic', 'blocked']
    tool: Optional[Literal['inventory', 'order', 'quotation']] = None
    sku: Optional[str] = None
    entity_id: Optional[int] = None
    blocked_reason: Optional[str] = None


# ── Main function ─────────────────────────────────────────────────────────────

def parse_question(question: str) -> ParsedQuery:
    # 1. Blocked — checked first; must never miss (100% recall required)
    for pattern in _BLOCKED:
        if pattern.search(question):
            return ParsedQuery(route='blocked', blocked_reason=pattern.pattern)

    # 2. Extract identifiers
    sku_match = SKU_PATTERN.search(question)
    sku = sku_match.group(1) if sku_match else None

    id_match = NUMERIC_ID_PATTERN.search(question)
    entity_id: Optional[int] = None
    if id_match:
        raw = id_match.group(1) or id_match.group(2)
        entity_id = int(raw) if raw else None

    # 3. Dynamic: inventory query with SKU
    if sku:
        for pattern in _INVENTORY_DYNAMIC:
            if pattern.search(question):
                return ParsedQuery(route='dynamic', tool='inventory', sku=sku)

    # 4. Dynamic: quotation query with numeric ID (check before order — a quotation
    #    question often mentions "轉成訂單" which would otherwise trigger the order branch)
    if entity_id and re.search(r'報價|quotation', question, re.IGNORECASE):
        return ParsedQuery(route='dynamic', tool='quotation', entity_id=entity_id)

    # 5. Dynamic: order query with numeric ID
    if entity_id and re.search(r'訂單|order', question, re.IGNORECASE):
        return ParsedQuery(route='dynamic', tool='order', entity_id=entity_id)

    # 6. Default: static (RAG)
    return ParsedQuery(route='static')
