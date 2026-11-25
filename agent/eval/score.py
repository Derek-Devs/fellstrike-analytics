"""Scores a run of the agent's eval and writes agent/eval/report.md (docs/analytics-design.md, section 10.3).

Run from this repository's root, with the environment active:
    python agent\\eval\\score.py                   the newest run
    python agent\\eval\\score.py 20261123-1830     one run, by its folder in agent/eval/runs

An answerable question passes when:
- the RESULT line's value is within 0.5% of what the question's own SQL returned when the run started (saved in the
  run's run.json, or worked out now for a run made before that was saved)
- the agent queried one of the question's metrics, with the question's source or both
An unanswerable question passes when the RESULT value is null. Whether the answer showed its SQL and named its
source is reported beside the score. Both are looked for in the answer above its RESULT line, since the RESULT line
always holds a source.
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
run_info = json.loads((run / "run.json").read_text(encoding="utf-8"))
model = run_info["model"]
saved_expected = run_info.get("expected", {})
questions = yaml.safe_load((EVAL / "questions.yaml").read_text(encoding="utf-8"))["questions"]
# The answer names its source when it says simulated, or real next to players, data, events or runs, or the source.
SOURCE_NAMED = re.compile(r"\bsimulated\b|\breal (players?|data|events|runs)\b|\breal \(live|source[^\n]{0,15}\breal\b",
                          re.IGNORECASE)


def close(a, b):
    return abs(a - b) <= 0.005 * abs(b) if b else a == 0


def expected_for(q, conn):
    """The run's saved right answer, or for an older run, what the question's SQL returns now. None when it's empty."""
    if q["id"] in saved_expected:
        return saved_expected[q["id"]]
    row = conn.execute(q["sql"]).fetchone()
    return None if row is None or row[0] is None else float(row[0])


def score(q, conn):
    """(passed, what the agent said, expected, why it missed, {sql shown, source named}, tool calls, cost)"""
    answer_file = run / f"{q['id']}.json"
    if not answer_file.exists():
        return None
    try:
        answer = json.loads(answer_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        answer = {"is_error": True, "result": answer_file.read_text(encoding="utf-8")}
    text = answer.get("result") or ""
    log = run / f"{q['id']}.tools.jsonl"
    calls = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()] if log.exists() else []
    queries = [c for c in calls if c["tool"] == "query_metrics" and "error" not in c]
    found = re.findall(r"RESULT:\s*(\{.*\})", text)
    # A RESULT line that isn't JSON (a number written 1,234, say) fails this question only.
    try:
        result = json.loads(found[-1]) if found else None
    except json.JSONDecodeError:
        result = None
    no_result = "no RESULT line" if not found else f"a RESULT line that isn't JSON ({found[-1][:80]!r})"
    value = result.get("value") if result else None
    body = text[:text.rfind("RESULT:")] if found else text
    shown = {"sql": bool(re.search(r"\bselect\b[\s\S]+\bfrom\b", body, re.IGNORECASE)),
             "source": bool(SOURCE_NAMED.search(body))}
    cost = answer.get("total_cost_usd") or 0

    if not q.get("answerable", True):
        # A refusal runs no query, so it has no SQL or source to show.
        shown = {"sql": None, "source": None}
        passed = result is not None and value is None
        why = "" if passed else (no_result if result is None else f"gave {value} for a question no metric answers")
        return passed, value, "no number", why, shown, len(calls), cost

    expected = expected_for(q, conn)
    if expected is None:
        return False, value, "nothing", "the question's own SQL returned no value", shown, len(calls), cost
    right_query = any(set(q["metrics"]) & set(c["arguments"]["metrics"]) and c["arguments"]["source"] in (q["source"], "both")
                      for c in queries)
    try:
        right_value = value is not None and close(float(value), expected)
    except (TypeError, ValueError):
        right_value = False
    why = []
    if result is None:
        why.append(no_result + (f" ({text[:120]!r})" if answer.get("is_error") else ""))
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
