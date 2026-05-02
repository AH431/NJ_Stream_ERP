"""
query_router.py — Top-level routing decision for the AI chat endpoint.

Wraps query_parser and adds customer contact query detection.

Route:  static | dynamic | blocked
Tool:   inventory | order | quotation | customer | None

Design intent (PRD v5.0 §3.2):
  query_parser  — regex extraction (SKU, numeric ID, blocked keywords)
  query_router  — higher-level routing, including customer live-data detection
"""

from __future__ import annotations

from src.tools.query_parser import ParsedQuery, parse_question

# "安全庫存水位設定是多少" asks about a *configured* stock level (static RAG card),
# not current live inventory.  The inventory dynamic patterns match "庫存…多少"
# too broadly, so we de-escalate here.
_STOCK_LEVEL_STATIC = re.compile(r'水位.{0,5}設定|安全庫存水位')

def route(question: str) -> ParsedQuery:
    """Return the routing decision for a user question."""
    parsed = parse_question(question)

    # De-escalate: configured stock level question → static (answered from RAG card)
    if (parsed.route == 'dynamic' and parsed.tool == 'inventory'
            and _STOCK_LEVEL_STATIC.search(question)):
        return ParsedQuery(route='static')

    # Upgrade: customer detail questions still need a search term before using live lookup.
    if parsed.tool == 'customer' and not parsed.search_term:
        return ParsedQuery(route='static')

    return parsed
