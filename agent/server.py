"""The Fellstrike metrics agent's MCP server (docs/analytics-design.md, section 10).

Claude reaches the warehouse only through these three tools, and every number comes from MetricFlow:
- list_metrics: every metric, with its type and what it means
- describe_metric: what one metric can be grouped and filtered by
- query_metrics: runs a query and returns its rows and the SQL that ran

There is no SQL tool. Each filter names a dimension, an operator and a value, the dimension is checked against the
metric's own list, and the value goes into the query as a quoted literal. So nothing in a question can reach the SQL
as code. Each call is logged as one line of JSON to agent/logs/tool_calls.jsonl, or to the file in AGENT_LOG.
"""
import contextlib
import datetime
import decimal
import json
import os
import pathlib
import sys
import time
from typing import Literal

from dotenv import load_dotenv
from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from pydantic import BaseModel

AGENT = pathlib.Path(__file__).resolve().parent
LOG = pathlib.Path(os.environ.get("AGENT_LOG") or AGENT / "logs" / "tool_calls.jsonl")
GRAINS = ["day", "week", "month", "quarter", "year"]

# MetricFlow reads the dbt project from the working folder and the warehouse login from .env. MCP talks
# over stdout, so anything dbt prints while it loads goes to stderr instead.
os.chdir(AGENT.parent / "dbt")
load_dotenv(AGENT.parent / ".env")
with contextlib.redirect_stdout(sys.stderr):
    from dbt_metricflow.cli.cli_configuration import CLIConfiguration
    from metricflow.engine.metricflow_engine import MetricFlowQueryRequest

    config = CLIConfiguration()
    config.setup(configure_file_logging=False)
    engine = config.mf
    METRICS = {metric.name: metric for metric in engine.list_metrics()}

server = MCPServer("fellstrike-metrics", instructions=(AGENT / "instructions.md").read_text(encoding="utf-8"))


class Filter(BaseModel):
    """One condition. For time dimensions the value is a date, 2026-10-12, and the grain is part of the name."""

    dimension: str
    operator: Literal["=", "!=", "<", "<=", ">", ">=", "in", "not in"]
    value: str | int | float | bool | list[str | int | float]


def log(tool, arguments, **outcome):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = {"at": datetime.datetime.now().isoformat(timespec="seconds"), "tool": tool, "arguments": arguments, **outcome}
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(line, default=str) + "\n")


def dimensions_for(metric_names):
    """{name: kind} for everything these metrics can be grouped and filtered by. Time dimensions get one name per
    grain (run__started_date__week). source is an entity every mart shares."""
    found = {"source": "entity"}
    with contextlib.redirect_stdout(sys.stderr):
        dimensions = engine.list_dimensions(metric_names=metric_names)
    for dimension in dimensions:
        name = dimension.dunder_name
        if str(dimension.type).endswith("TIME"):
            base = name.removesuffix("__day") if name.startswith("metric_time") else name
            for grain in GRAINS:
                found[f"{base}__{grain}"] = "time"
        else:
            found[name] = "categorical"
    return found


def literal(value, kind):
    """A value as a SQL literal. Text is quoted with its quotes doubled, and braces are refused, since MetricFlow reads
    filters as templates."""
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)) and kind != "time":
        return repr(value)
    text = str(value)
    if any(c in text for c in "{}\n\r"):
        raise ToolError(f"Filter value {text!r} holds characters a filter can't take")
    if kind == "time":
        try:
            datetime.date.fromisoformat(text)
        except ValueError:
            raise ToolError(f"A time filter takes a date like 2026-10-12, not {text!r}") from None
    return "'" + text.replace("'", "''") + "'"


def where_clause(item, dimensions):
    kind = dimensions.get(item.dimension)
    if kind is None:
        raise ToolError(f"{item.dimension!r} isn't a dimension these metrics have. Use describe_metric to see them.")
    if kind == "entity":
        reference = "{{ Entity('source') }}"
    elif kind == "time":
        base, grain = item.dimension.rsplit("__", 1)
        reference = f"{{{{ TimeDimension('{base}', '{grain}') }}}}"
    else:
        reference = f"{{{{ Dimension('{item.dimension}') }}}}"
    if item.operator in ("in", "not in"):
        values = item.value if isinstance(item.value, list) else [item.value]
        if not values:
            raise ToolError(f"Operator {item.operator} takes at least one value, not an empty list")
        return f"{reference} {item.operator.upper()} ({', '.join(literal(v, kind) for v in values)})"
    if isinstance(item.value, list):
        raise ToolError(f"Operator {item.operator} takes one value, not a list")
    return f"{reference} {item.operator} {literal(item.value, kind)}"


def plain(value):
    """A cell as something JSON can hold."""
    if isinstance(value, decimal.Decimal):
        return float(value)
    if isinstance(value, (datetime.date, datetime.datetime)):
        return value.isoformat()
    return value


@server.tool()
def list_metrics() -> dict:
    """Every metric in the semantic layer: its name, label, type (simple, ratio or derived) and what it means."""
    found = [{"name": m.name, "label": m.label, "type": str(m.type.value), "description": m.description}
             for m in sorted(METRICS.values(), key=lambda m: m.name)]
    log("list_metrics", {}, metrics=len(found))
    return {"metrics": found}


@server.tool()
def describe_metric(name: str) -> dict:
    """One metric in full: what it means, and every dimension it can be grouped and filtered by. Time dimensions are
    listed once per grain (day, week, month, quarter, year). metric_time is each metric's own main date."""
    if name not in METRICS:
        log("describe_metric", {"name": name}, error="unknown metric")
        raise ToolError(f"No metric is called {name!r}. Use list_metrics to see them.")
    metric = METRICS[name]
    dimensions = dimensions_for([name])
    log("describe_metric", {"name": name}, dimensions=len(dimensions))
    return {"name": name, "label": metric.label, "type": str(metric.type.value), "description": metric.description,
            "dimensions": dimensions}


@server.tool()
def query_metrics(
    metrics: list[str],
    source: Literal["real", "simulated", "both"],
    group_by: list[str] | None = None,
    filters: list[Filter] | None = None,
    order_by: list[str] | None = None,
    limit: int = 100,
) -> dict:
    """Runs a query through MetricFlow and returns its rows and the SQL that ran.

    metrics: metric names from list_metrics. Several can go in one query.
    source: "simulated" (bot-played runs), "real" (live players) or "both". Every row says its source.
    group_by: dimension names from describe_metric, such as run__mode or metric_time__week.
    filters: conditions, such as {"dimension": "run__mode", "operator": "=", "value": "endless"}.
    order_by: metric or group_by names, with a leading - for largest first, such as "-runs_started".
    limit: at most 200 rows.
    """
    arguments = {"metrics": metrics, "source": source, "group_by": group_by, "filters": [f.model_dump() for f in filters or []],
                 "order_by": order_by, "limit": limit}
    try:
        unknown = [m for m in metrics if m not in METRICS]
        if not metrics or unknown:
            raise ToolError(f"Unknown metrics {unknown}. Use list_metrics to see them.")
        dimensions = dimensions_for(metrics)
        group_by = list(dict.fromkeys(["source", *(group_by or [])]))
        for name in group_by:
            if name not in dimensions:
                raise ToolError(f"Can't group by {name!r}. Use describe_metric to see the dimensions.")
        wheres = [where_clause(f, dimensions) for f in filters or []]
        if source != "both":
            wheres.append(f"{{{{ Entity('source') }}}} = '{source}'")
        for name in order_by or []:
            if name.lstrip("-") not in metrics + group_by:
                raise ToolError(f"Can only order by the query's own metrics and groupings, not {name!r}")
        limit = max(1, min(int(limit), 200))

        started = time.time()
        with contextlib.redirect_stdout(sys.stderr):
            result = engine.query(MetricFlowQueryRequest.create(
                metric_names=metrics, group_by_names=group_by, where_constraints=wheres or None,
                order_by_names=order_by or None, limit=limit))
        table = result.result_df
        rows = [dict(zip(table.column_names, map(plain, row))) for row in table.rows]
    except ToolError as error:
        log("query_metrics", arguments, error=str(error))
        raise
    except Exception as error:
        # MetricFlow refused the query, for example two metrics with no grouping in common. Its message says why.
        log("query_metrics", arguments, error=str(error))
        raise ToolError(f"MetricFlow couldn't run this query: {str(error)[:800]}") from None
    log("query_metrics", arguments, rows=len(rows), seconds=round(time.time() - started, 2), sql=result.sql)
    return {"source": source, "metrics": metrics, "group_by": group_by, "filters": wheres, "rows": rows,
            "row_count": len(rows), "may_be_cut_off": len(rows) == limit, "sql": result.sql}


if __name__ == "__main__":
    server.run("stdio")
