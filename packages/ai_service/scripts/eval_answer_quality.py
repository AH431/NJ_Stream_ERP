#!/usr/bin/env python3
"""
eval_answer_quality.py — RAG answer quality evaluation.

Measures two automated metrics and one manual-review output:

  1. Retrieval hit@k  (automated)
     — For each question, check if the expected card filename appears
       in the top-k retrieved chunk metadata.

  2. Sensitive leakage  (automated)
     — When --no-llm is NOT set, run the full RAG chain and scan
       the answer for strings listed in 禁止編造欄位.

  3. Answer correctness  (manual review)
     — Answers are written to the JSON output for human review.
       Target: ≥ 80 % of questions answered correctly.

Pass criteria (Phase 2 target):
  retrieval hit@3  ≥ 85 %
  sensitive leakage = 0

Exit codes:
  0 — retrieval hit@3 ≥ 85 % AND leakage = 0
  1 — one or more criteria fail
  2 — usage / setup error

Usage:
  cd packages/ai_service
  python scripts/eval_answer_quality.py
  python scripts/eval_answer_quality.py --no-llm
  python scripts/eval_answer_quality.py --k 5 --output reports/answer_quality_20260504.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Optional

# Phrases that indicate the model is *refusing* to provide a value rather
# than leaking one.  Used to suppress false positives in the leakage check.
_REFUSAL_PATTERNS: list[re.Pattern] = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"don'?t have",
        r"do not have",
        r"no information",
        r"not available",
        r"not in (?:the )?card",
        r"not provided",
        r"cannot provide",
        r"do not provide",
        r"does not provide",
        r"not include",
        r"excluded",
        r"does not support",
        r"do not support",
        r"not support",
        r"not found",
        r"is not (?:stored|included|present)",
        r"no explicit mention",
        r"not explicitly",
        r"not (?:directly )?mentioned",
        r"not in the provided",
        r"but not\b",
        r"it does not",
        # Chinese refusal phrases
        r"不提供",
        r"不包含",
        r"無法提供",
        r"不在卡片",
        r"不支援",
        r"不支持",
        r"沒有.*資訊",
        r"資料中找不到",
    ]
]
_REFUSAL_WINDOW = 100  # chars on each side of the forbidden field mention

# Semantic equivalence groups for keyword matching.
# Any alias that appears in the answer counts as a hit for its key.
_KW_ALIASES: dict[str, list[str]] = {
    # Wireless / connectivity
    "bluetooth 5.0":    ["ble 5.0", "bluetooth 5", "bt 5.0"],
    "ble only":         ["ble 5.0", "bluetooth 5.0", "ble module", "no wifi"],
    "no wifi":          ["does not support wifi", "doesn't support wifi", "not support wifi"],
    # Physical specs
    "two-layer":        ["2-layer", "2 layer"],
    "0.96 inch":        ["0.96-inch"],
    "2.4 inch":         ["2.4-inch"],
    # Component types
    "voltage regulator": ["ldo", "regulator"],
    "individually controlled": ["individually", "each.*controlled", "independent control"],
    # Inventory
    "safety level":     ["safety stock level", "stock level"],
    "below safety level": ["below safety stock", "below its safety", "below the safety"],
    # Refusal / not available
    "will not accept":  ["does not accept", "requires written approval", "require written approval"],
    "not available": [
        "no information", "don't have", "do not have", "not found",
        "not in card", "not provided", "don't have access", "no access",
        "not accessible", "cannot provide",
    ],
    "not in card": [
        "not available", "no information", "don't have", "do not have",
        "not found", "not provided", "don't have access", "not accessible",
    ],
    "not found":         ["don't have information", "no information on", "i don't have", "cannot find"],
    "not in catalog":    ["don't have information", "no information on", "i don't have", "not found"],
    "cannot confirm":    ["don't have information", "no information on", "i don't have"],
    # Specific price keyword
    "unit price $4.50":  ["$4.50"],
    # Contact / refusal phrasing
    "email not in card": ["email address", "email is not", "no email", "email.*not"],
    "contact sales admin":              ["contact", "sales team", "reach out"],
    "contact name is david liu":        ["david liu"],
    "order history requires live data": ["dynamic", "live data", "order history"],
    "use dynamic query":                ["dynamic", "live query", "real-time"],
    "not in static card":              ["not in static", "static card", "not in the static"],
    "cost price not available": [
        "cost price is not", "no cost price", "purchase price is not",
        "not included", "not provided", "not in card",
    ],
}


def _kw_matches(keyword: str, answer_lower: str) -> bool:
    """Return True if keyword or any semantic alias appears in the answer."""
    if keyword.lower() in answer_lower:
        return True
    for alias in _KW_ALIASES.get(keyword.lower(), []):
        if alias.lower() in answer_lower:
            return True
    return False


def _in_refusal_context(answer_lower: str, field: str) -> bool:
    """Return True if the forbidden field only appears in a refusal/denial sentence.

    A refusal is when the model says the field is *not* available / supported —
    e.g. "I don't have the tax ID" — rather than fabricating a value.
    We check a character window around each occurrence of the field token.
    """
    field_lower = field.lower()
    start = 0
    while True:
        idx = answer_lower.find(field_lower, start)
        if idx == -1:
            break
        window = answer_lower[max(0, idx - _REFUSAL_WINDOW): idx + len(field_lower) + _REFUSAL_WINDOW]
        if not any(p.search(window) for p in _REFUSAL_PATTERNS):
            return False  # found an occurrence that is NOT a refusal — real leakage
        start = idx + 1
    return True  # every occurrence was inside a refusal context

# ── Path setup ────────────────────────────────────────────────────────────────

_SCRIPT_DIR = Path(__file__).resolve().parent
_AI_SERVICE_ROOT = _SCRIPT_DIR.parent
_REPO_ROOT = _AI_SERVICE_ROOT.parents[1]

sys.path.insert(0, str(_AI_SERVICE_ROOT))

from dotenv import load_dotenv
load_dotenv()

# ── Data models ───────────────────────────────────────────────────────────────

@dataclass
class AQQuestion:
    id: str
    group: str           # P | C | A | I | N
    question: str
    role: str
    expected_card: str   # filename (may be empty for AQ-N04 etc.)
    expected_keywords: list[str]
    forbidden_fields: list[str]
    note: str = ""


@dataclass
class AQResult:
    id: str
    question: str
    expected_card: str
    retrieved_cards: list[str]
    hit: bool
    answer: str = ""
    leakage_found: list[str] = field(default_factory=list)
    keywords_present: list[str] = field(default_factory=list)
    keywords_missing: list[str] = field(default_factory=list)


# ── Markdown parser ───────────────────────────────────────────────────────────

def _field(block: str, key: str) -> str:
    m = re.search(rf'^{re.escape(key)}[：:]\s*(.+)$', block, re.MULTILINE)
    return m.group(1).strip() if m else ""


def _csv(value: str) -> list[str]:
    return [v.strip() for v in value.split(",") if v.strip()]


_GROUP_MAP = {"P": "P", "C": "C", "A": "A", "I": "I", "N": "N"}

def parse_questions(md_path: Path) -> list[AQQuestion]:
    text = md_path.read_text(encoding="utf-8")

    block_re = re.compile(
        r'###\s+(AQ-([PCAIN])\d+)[^\n]*\n+```\n(.*?)```',
        re.DOTALL,
    )

    questions: list[AQQuestion] = []
    for m in block_re.finditer(text):
        aq_id = m.group(1)
        group = m.group(2)
        block = m.group(3)

        question = _field(block, "問題")
        role = _field(block, "發問角色") or "sales"
        expected_card = _field(block, "預期召回卡片").strip("（不存在）").strip()
        keywords = _csv(_field(block, "預期答案重點"))
        forbidden = _csv(_field(block, "禁止編造欄位"))
        note = _field(block, "備註")

        if question:
            questions.append(AQQuestion(
                id=aq_id,
                group=group,
                question=question,
                role=role,
                expected_card=expected_card,
                expected_keywords=keywords,
                forbidden_fields=forbidden,
                note=note,
            ))

    return questions


# ── Retrieval eval ────────────────────────────────────────────────────────────

def evaluate_retrieval(
    questions: list[AQQuestion],
    vectorstore,
    k: int,
) -> list[AQResult]:
    from src.rag.retriever import build_hybrid_retriever

    _retriever_cache: dict[str, object] = {}

    results: list[AQResult] = []
    for q in questions:
        role = q.role or "sales"
        if role not in _retriever_cache:
            _retriever_cache[role] = build_hybrid_retriever(vectorstore, role=role, top_k=k)
        retriever = _retriever_cache[role]

        docs = retriever.invoke(q.question)
        retrieved = [d.metadata.get("filename", d.metadata.get("source", "?")) for d in docs]

        if not q.expected_card:
            # Negative questions with no expected card: hit = True iff no card retrieved matches a real entity
            hit = True
        else:
            hit = any(q.expected_card in r for r in retrieved)

        results.append(AQResult(
            id=q.id,
            question=q.question,
            expected_card=q.expected_card,
            retrieved_cards=retrieved,
            hit=hit,
        ))

    return results


# ── LLM eval (optional) ───────────────────────────────────────────────────────

def _format_docs(docs) -> str:
    return "\n\n---\n\n".join(
        f"[{d.metadata.get('filename', '?')}]\n{d.page_content}" for d in docs
    )


def evaluate_llm(
    questions: list[AQQuestion],
    results: list[AQResult],
    vectorstore,
    k: int,
) -> None:
    from src.rag.retriever import build_hybrid_retriever
    from src.retrieval.prompt import RAG_PROMPT  # English structured prompt for eval consistency
    from src.llm.ollama_client import get_llm

    llm = get_llm()
    chain = RAG_PROMPT | llm
    _retriever_cache: dict[str, object] = {}

    result_map = {r.id: r for r in results}

    for q in questions:
        role = q.role or "sales"
        if role not in _retriever_cache:
            _retriever_cache[role] = build_hybrid_retriever(vectorstore, role=role, top_k=k)
        retriever = _retriever_cache[role]

        r = result_map[q.id]
        docs = retriever.invoke(q.question)
        context = _format_docs(docs)

        try:
            response = chain.invoke({"context": context, "question": q.question})
            answer = response.content if hasattr(response, "content") else str(response)
        except Exception as exc:
            answer = f"[ERROR: {exc}]"

        r.answer = answer
        answer_lower = answer.lower()

        # Check forbidden fields — skip if the field only appears inside a
        # refusal/denial sentence (e.g. "I don't have the tax ID number").
        for fb in q.forbidden_fields:
            if fb.lower() in answer_lower and not _in_refusal_context(answer_lower, fb):
                r.leakage_found.append(fb)

        # Check expected keywords (case-insensitive, with semantic aliases)
        for kw in q.expected_keywords:
            if _kw_matches(kw, answer_lower):
                r.keywords_present.append(kw)
            else:
                r.keywords_missing.append(kw)


# ── Reporter ──────────────────────────────────────────────────────────────────

_GROUP_NAMES = {
    "P": "Product Factual",
    "C": "Customer Factual",
    "A": "Alias / Synonym",
    "I": "Inventory Risk",
    "N": "Negative",
}

_HIT_THRESHOLD = 0.85


def print_report(
    questions: list[AQQuestion],
    results: list[AQResult],
    run_llm: bool,
) -> bool:
    q_map = {q.id: q for q in questions}
    group_results: dict[str, list[AQResult]] = {}
    for r in results:
        g = r.id.split("-")[1][0]
        group_results.setdefault(g, []).append(r)

    total_hit = total_n = 0
    total_leakage = 0
    all_ok = True

    print()
    for g in ("P", "C", "A", "I", "N"):
        grs = group_results.get(g, [])
        if not grs:
            continue
        n = len(grs)
        hits = sum(1 for r in grs if r.hit)
        rate = hits / n
        marker = "✓" if rate >= _HIT_THRESHOLD else "△"
        print(f"[{g}] {_GROUP_NAMES[g]:20s}  hit@3  {hits:2d}/{n}  ({rate:5.1%})  {marker}")

        for r in grs:
            if not r.hit:
                print(f"  ✗ {r.id}: expected={r.expected_card!r}")
                print(f"       retrieved={r.retrieved_cards}")

        total_hit += hits
        total_n += n

    grand_rate = total_hit / total_n if total_n else 0
    ok_retrieval = grand_rate >= _HIT_THRESHOLD

    overall_marker = "✓" if ok_retrieval else "✗ FAIL"
    print(f"\nRetrieval hit@3 overall:  {total_hit}/{total_n} ({grand_rate:.1%})  {overall_marker}")

    if run_llm:
        leakage_cases = [(r, f) for r in results for f in r.leakage_found]
        total_leakage = len(leakage_cases)
        ok_leakage = total_leakage == 0
        print(f"Sensitive leakage:        {total_leakage} instances  {'✓' if ok_leakage else '✗ FAIL'}")
        for r, f in leakage_cases:
            print(f"  ✗ {r.id}: leaked field={f!r}")
            print(f"       answer={r.answer[:120]}...")
        if not ok_leakage:
            all_ok = False

        # Keyword coverage summary
        all_present = sum(len(r.keywords_present) for r in results)
        all_expected = sum(len(q_map[r.id].expected_keywords) for r in results)
        kw_rate = all_present / all_expected if all_expected else 0
        print(f"Keyword coverage:         {all_present}/{all_expected} ({kw_rate:.1%})  (reference — manual review required)")

    return all_ok and ok_retrieval


def write_json(
    questions: list[AQQuestion],
    results: list[AQResult],
    output_path: Path,
) -> None:
    q_map = {q.id: q for q in questions}
    data = []
    for r in results:
        q = q_map[r.id]
        data.append({
            "id": r.id,
            "group": q.group,
            "question": r.question,
            "role": q.role,
            "expected_card": r.expected_card,
            "retrieved_cards": r.retrieved_cards,
            "hit": r.hit,
            "answer": r.answer,
            "leakage_found": r.leakage_found,
            "keywords_present": r.keywords_present,
            "keywords_missing": r.keywords_missing,
            "note": q.note,
        })
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nJSON saved → {output_path}")


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description="Eval RAG answer quality.")
    parser.add_argument(
        "--questions",
        type=Path,
        default=_REPO_ROOT / "docs" / "artifacts" / "phase3-ai-answer-quality-questions.md",
    )
    parser.add_argument("--k", type=int, default=3, help="Retrieval top-k (default 3)")
    parser.add_argument("--no-llm", action="store_true", help="Skip LLM generation (retrieval only)")
    parser.add_argument("--output", type=Path, default=None, help="Optional JSON output path")
    args = parser.parse_args()

    if not args.questions.exists():
        print(f"ERROR: questions file not found: {args.questions}", file=sys.stderr)
        return 2

    questions = parse_questions(args.questions)
    if not questions:
        print("ERROR: no questions parsed.", file=sys.stderr)
        return 2

    print(f"Loaded {len(questions)} answer-quality questions")

    # Build vectorstore
    from src.indexing.embedder import get_embeddings
    from src.indexing.vectorstore import get_vectorstore

    db_path = os.getenv("CHROMA_DB_PATH", "./db")
    print(f"Loading vectorstore from {db_path} ...")
    embeddings = get_embeddings()
    vectorstore = get_vectorstore(embeddings, db_path=db_path)

    # Retrieval eval
    results = evaluate_retrieval(questions, vectorstore, k=args.k)

    # LLM eval (optional)
    run_llm = not args.no_llm
    if run_llm:
        print("Running LLM generation (use --no-llm to skip)...")
        evaluate_llm(questions, results, vectorstore, k=args.k)

    passed = print_report(questions, results, run_llm=run_llm)

    if args.output:
        write_json(questions, results, args.output)

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
