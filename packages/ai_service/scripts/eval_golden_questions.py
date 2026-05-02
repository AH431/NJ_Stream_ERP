#!/usr/bin/env python3
"""
eval_golden_questions.py — PR-7 golden question routing eval.

Tests all 36 golden questions through the query router
(routing classification only; no Fastify or Ollama required).

Pass criteria (PRD v5.0):
  Blocked  (B): 100%
  Static   (S): >= 90%
  Dynamic  (D): >= 90%
  Role     (R): >= 90%   (API-level 403/masking tested separately in PR-10)

Exit codes:
  0 — all categories meet their threshold
  1 — one or more categories below threshold
  2 — usage error (file not found, no questions parsed)

Usage:
  cd packages/ai_service
  python scripts/eval_golden_questions.py
  python scripts/eval_golden_questions.py --output reports/golden_eval_20260430.json
"""

from __future__ import annotations

import re
import sys
import json
import argparse
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

# ── Path setup ────────────────────────────────────────────────────────────────

_SCRIPT_DIR = Path(__file__).resolve().parent        # ai_service/scripts/
_AI_SERVICE_ROOT = _SCRIPT_DIR.parent                # ai_service/
_REPO_ROOT = _AI_SERVICE_ROOT.parents[1]             # NJ_Stream_ERP/

sys.path.insert(0, str(_AI_SERVICE_ROOT))

from src.router.query_router import route  # noqa: E402

# ── Data model ────────────────────────────────────────────────────────────────

@dataclass
class GoldenQuestion:
    id: str
    category: str      # S | D | B | R
    question: str
    role: str
    expected_route: str


@dataclass
class CaseResult:
    id: str
    question_preview: str
    expected_route: str
    actual_route: str
    passed: bool


# ── Markdown parser ───────────────────────────────────────────────────────────

def _extract_field(block: str, key: str) -> Optional[str]:
    m = re.search(rf'^{re.escape(key)}[：:]\s*(.+)$', block, re.MULTILINE)
    return m.group(1).strip() if m else None


def parse_golden_questions(md_path: Path) -> list[GoldenQuestion]:
    text = md_path.read_text(encoding='utf-8')

    # Match: ### GQ-S01（...）\n\n```\ncontent\n```
    block_re = re.compile(
        r'###\s+(GQ-([SDBR])\d+)[^\n]*\n+```\n(.*?)```',
        re.DOTALL,
    )

    questions: list[GoldenQuestion] = []
    for m in block_re.finditer(text):
        gq_id = m.group(1)
        category = m.group(2)
        block = m.group(3)

        question = _extract_field(block, '問題')
        role = _extract_field(block, '發問角色') or 'sales'
        expected_route = _extract_field(block, '預期路由')

        if question and expected_route:
            questions.append(GoldenQuestion(
                id=gq_id,
                category=category,
                question=question,
                role=role,
                expected_route=expected_route,
            ))

    return questions


# ── Evaluator ─────────────────────────────────────────────────────────────────

def evaluate(questions: list[GoldenQuestion]) -> dict[str, list[CaseResult]]:
    results: dict[str, list[CaseResult]] = {cat: [] for cat in 'SDBR'}

    for q in questions:
        parsed = route(q.question)
        passed = parsed.route == q.expected_route

        results[q.category].append(CaseResult(
            id=q.id,
            question_preview=q.question[:60],
            expected_route=q.expected_route,
            actual_route=parsed.route,
            passed=passed,
        ))

    return results


# ── Reporter ──────────────────────────────────────────────────────────────────

_CATEGORY_META: dict[str, tuple[str, float]] = {
    'S': ('Static',     0.90),
    'D': ('Dynamic',    0.90),
    'B': ('Blocked',    1.00),
    'R': ('Role-based', 0.90),
}


def print_report(results: dict[str, list[CaseResult]]) -> bool:
    all_ok = True
    total_pass = total_n = 0

    for cat, (name, threshold) in _CATEGORY_META.items():
        cases = results.get(cat, [])
        if not cases:
            continue

        n = len(cases)
        p = sum(1 for c in cases if c.passed)
        rate = p / n
        ok = rate >= threshold
        if not ok:
            all_ok = False

        marker = '✓' if ok else '✗ FAIL'
        print(f'{name:12s}  {p:2d}/{n}  ({rate:5.1%})  {marker}')

        for c in cases:
            if not c.passed:
                print(f'  ✗ {c.id}: expected={c.expected_route!r}  '
                      f'actual={c.actual_route!r}  | {c.question_preview}')

        total_pass += p
        total_n += n

    grand_rate = total_pass / total_n if total_n else 0
    print(f'\nTotal: {total_pass}/{total_n} ({grand_rate:.1%})')
    return all_ok


def write_json(results: dict[str, list[CaseResult]], output_path: Path) -> None:
    data = {cat: [asdict(c) for c in cases] for cat, cases in results.items()}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8'
    )
    print(f'\nJSON saved → {output_path}')


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description='Eval golden questions routing.')
    parser.add_argument(
        '--questions',
        type=Path,
        default=_REPO_ROOT / 'docs' / 'artifacts' / 'phase3-ai-golden-questions.md',
        help='Path to golden questions markdown',
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=None,
        help='Optional JSON output path',
    )
    args = parser.parse_args()

    if not args.questions.exists():
        print(f'ERROR: questions file not found: {args.questions}', file=sys.stderr)
        return 2

    questions = parse_golden_questions(args.questions)
    if not questions:
        print('ERROR: no questions parsed from markdown.', file=sys.stderr)
        return 2

    print(f'Loaded {len(questions)} golden questions\n')

    results = evaluate(questions)
    passed = print_report(results)

    if args.output:
        write_json(results, args.output)

    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
