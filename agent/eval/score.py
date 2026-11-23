"""Scores a run of the agent's eval and writes agent/eval/report.md (docs/analytics-design.md, section 10.3).

Run from the analytics folder, with the environment active:
    python agent\\eval\\score.py                   the newest run
    python agent\\eval\\score.py 20261123-1830     one run, by its folder in agent/eval/runs

An answerable question passes when:
- the RESULT line's value is within 0.5% of what the question's own SQL returns
- the agent queried one of the question's metrics, with the question's source or both
An unanswerable question passes when the RESULT value is null. Whether the answer showed its SQL and named its
source is reported beside the score.
"""
import json
import os
import pathlib
import re
import sys

import psycopg
import yaml
from dotenv import load_dotenv

EVAL = pathlib.Path(__file__).resolve().parent
load_dotenv(EVAL.parent.parent / ".env")
runs = sorted(p for p in (EVAL / "runs").iterdir() if p.is_dir())
run = EVAL / "runs" / sys.argv[1] if sys.argv[1:] else runs[-1]
model = json.loads((run / "run.json").read_text(encoding="utf-8"))["model"]
questions = yaml.safe_load((EVAL / "questions.yaml").read_text(encoding="utf-8"))["questions"]


def close(a, b):
    return abs(a - b) <= 0.005 * abs(b) if b else a == 0


def score(q, conn):
    """(passed, what the agent said, expected, why it missed, {sql shown, source named}, tool calls, cost)"""
    answer_file = run / f"{q['id']}.json"
    if not answer_file.exists():
        return None
    answer = json.loads(answer_file.read_text(encoding="utf-8"))
    text = answer.get("result") or ""
    log = run / f"{q['id']}.tools.jsonl"
    calls = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()] if log.exists() else []
    queries = [c for c in calls if c["tool"] == "query_metrics" and "error" not in c]
    found = re.findall(r"RESULT:\s*(\{.*\})", text)
    result = json.loads(found[-1]) if found else None
    value = result.get("value") if result else None
    shown = {"sql": bool(re.search(r"\bselect\b[\s\S]+\bfrom\b", text, re.IGNORECASE)),
             "source": bool(re.search(r"\b(real|simulated)\b", text, re.IGNORECASE))}
    cost = answer.get("total_cost_usd") or 0

    if not q.get("answerable", True):
        # A refusal runs no query, so it has no SQL or source to show.
        shown = {"sql": None, "source": None}
        passed = result is not None and value is None
        why = "" if passed else ("no RESULT line" if result is None else f"gave {value} for a question no metric answers")
        return passed, value, "no number", why, shown, len(calls), cost

    expected = float(conn.execute(q["sql"]).fetchone()[0])
    right_query = any(set(q["metrics"]) & set(c["arguments"]["metrics"]) and c["arguments"]["source"] in (q["source"], "both")
                      for c in queries)
    try:
        right_value = value is not None and close(float(value), expected)
    except (TypeError, ValueError):
        right_value = False
    why = []
    if result is None:
        why.append("no RESULT line" + (f" ({text[:120]!r})" if answer.get("is_error") else ""))
    elif not right_value:
        why.append(f"said {value}, expected {expected:.6g}")
    if not right_query:
        used = sorted({m for c in queries for m in c["arguments"]["metrics"]}) or "nothing"
        why.append(f"queried {used}, not {q['metrics']} on {q['source']}")
    return right_value and right_query, value, expected, "; ".join(why), shown, len(calls), cost


with psycopg.connect(os.environ["WAREHOUSE_URL"]) as conn:
    scored = [(q, score(q, conn)) for q in questions]
scored = [(q, s) for q, s in scored if s]
passed = sum(1 for _, s in scored if s[0])

lines = [
    "# Agent eval report",
    "",
    f"Run `{run.name}` with `{model}`: **{passed} of {len(scored)} right.** "
    f"Of the {sum(1 for q, _ in scored if q.get('answerable', True))} answerable questions, "
    f"{sum(1 for _, s in scored if s[4]['sql'])} answers showed their SQL and "
    f"{sum(1 for _, s in scored if s[4]['source'])} named their source. "
    f"Cost as Claude Code reports it: ${sum(s[6] for _, s in scored):.2f}.",
    "",
    "Made by `agent/eval/score.py` from the answers in `agent/eval/runs/` (docs/analytics-design.md, section 10.3).",
    "",
    "| Question | Expected | Said | Right | SQL shown | Source named | Tool calls | Why it missed |",
    "|---|---|---|---|---|---|---|---|",
]
def yes_no(flag):
    return "n/a" if flag is None else "yes" if flag else "no"


for q, (ok, value, expected, why, shown, calls, _) in scored:
    expected_text = f"{expected:.6g}" if isinstance(expected, float) else expected
    lines.append(f"| {q['id']}: {q['question'].strip()} | {expected_text} | {value} | {yes_no(ok)} | "
                 f"{yes_no(shown['sql'])} | {yes_no(shown['source'])} | {calls} | {why} |")
(EVAL / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
