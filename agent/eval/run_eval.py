"""Runs the agent's eval (docs/analytics-design.md, section 10.3). Each question in questions.yaml goes to Claude Code
with the metrics server's three tools and nothing else, and its answer and tool calls are saved for score.py.

Run from this repository's root, with the environment active and the warehouse running:
    python agent\\eval\\run_eval.py              all 20 questions
    python agent\\eval\\run_eval.py q04 q17      some of them

It needs Claude Code signed in: run claude once and use /login. If claude isn't on PATH, set CLAUDE_CLI to its full
path. AGENT_MODEL picks the model (claude-sonnet-5-5 unless set).

Each question runs in a new empty folder outside the repository, so Claude Code loads no project memory and no
CLAUDE.md, and --tools "" leaves it no built-in tools: no files, no shell, no web. Answers land in
agent/eval/runs/<time>/, which git ignores. Each question's right answer, from its own SQL, is saved in run.json
before any question is asked, so a later reload of the warehouse can't change what the run is scored against. A
question that times out or gets no proper reply is saved as an error, and the others carry on.
"""
import concurrent.futures
import datetime
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import psycopg
import yaml
from dotenv import load_dotenv

EVAL = pathlib.Path(__file__).resolve().parent
AGENT = EVAL.parent
CLI = os.environ.get("CLAUDE_CLI", "claude")
MODEL = os.environ.get("AGENT_MODEL", "claude-sonnet-5-5")
SERVER = "fellstrike-metrics"
TOOLS = [f"mcp__{SERVER}__list_metrics", f"mcp__{SERVER}__describe_metric", f"mcp__{SERVER}__query_metrics"]
RESULT_RULE = (
    "This question is part of a test. After your answer, end with one line of this form and nothing after it:\n"
    'RESULT: {"value": <the number that answers the question, exactly as the tool returned it, or null when no '
    'metric answers it>, "source": "<real, simulated, or null>"}'
)

# The Claude desktop app passes its own session settings down to the programs it starts. Each test is a session of
# its own, so none of them are passed on. CLAUDE_CODE_OAUTH_TOKEN (from claude setup-token, in .env) is the one
# exception: it is a way to sign in.
load_dotenv(AGENT.parent / ".env")
ENV = {k: v for k, v in os.environ.items()
       if not k.upper().startswith(("CLAUDE", "ANTHROPIC", "MCP_")) or k == "CLAUDE_CODE_OAUTH_TOKEN"}


def ask(question, out):
    """Puts one question to Claude Code and saves its answer and the server's log of its tool calls."""
    log = out / f"{question['id']}.tools.jsonl"
    # A server still shutting down can hold the folder open on Windows, so a failed cleanup is ignored.
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as folder:
        config = pathlib.Path(folder) / "mcp.json"
        config.write_text(json.dumps({"mcpServers": {SERVER: {
            "command": sys.executable, "args": [str(AGENT / "server.py")], "env": {"AGENT_LOG": str(log)}}}}))
        try:
            done = subprocess.run(
                [CLI, "-p", question["question"], "--mcp-config", str(config), "--strict-mcp-config", "--tools", "",
                 "--allowedTools", *TOOLS, "--append-system-prompt", RESULT_RULE, "--model", MODEL,
                 "--output-format", "json", "--no-session-persistence", "--setting-sources", ""],
                cwd=folder, env=ENV, capture_output=True, text=True, encoding="utf-8", timeout=900)
            reply = done.stdout.strip() or done.stderr.strip()
        except subprocess.TimeoutExpired:
            reply = "timed out after 15 minutes"
    # Claude Code's reply is one JSON object. Anything else (a timeout, a warning, a crash) is saved as an error, so
    # score.py can read every file and the other questions carry on.
    try:
        answer = json.loads(reply)
    except json.JSONDecodeError:
        answer = None
    if not isinstance(answer, dict):
        answer = {"is_error": True, "result": reply}
    (out / f"{question['id']}.json").write_text(json.dumps(answer), encoding="utf-8")
    return question["id"], answer.get("is_error", True)


def expected_values(questions):
    """Each answerable question's right answer, from its own SQL. None when the SQL finds nothing."""
    values = {}
    with psycopg.connect(os.environ["WAREHOUSE_URL"]) as conn:
        for q in questions:
            if q.get("answerable", True):
                row = conn.execute(q["sql"]).fetchone()
                values[q["id"]] = None if row is None or row[0] is None else float(row[0])
    return values


questions = yaml.safe_load((EVAL / "questions.yaml").read_text(encoding="utf-8"))["questions"]
chosen = [q for q in questions if not sys.argv[1:] or q["id"] in sys.argv[1:]]
out = EVAL / "runs" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
out.mkdir(parents=True)  # a new folder every run, so no two runs' tool logs mix
(out / "run.json").write_text(json.dumps({"model": MODEL, "questions": [q["id"] for q in chosen],
                                          "expected": expected_values(chosen)}), encoding="utf-8")

# Four at a time: each one starts its own copy of the server, which loads MetricFlow.
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for qid, failed in pool.map(lambda q: ask(q, out), chosen):
        print(qid, "error" if failed else "answered")
print(f"Saved to {out}. Score it with: python agent\\eval\\score.py {out.name}")
