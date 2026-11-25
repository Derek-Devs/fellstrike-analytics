"""Checks that every MetricFlow metric gives the same number as the plain SQL in dbt/analyses/metric_values.sql.

Run it from the dbt folder, with the environment active (docs/analytics-design.md, section 8.4):
    python ..\\checks\\metrics_match_sql.py
It asks MetricFlow for every metric by source, runs the plain SQL, and lists any metric whose numbers differ or that
only one side has. It exits with 1 when there is one.
"""
import os
import sys

import psycopg

from semantic_layer import metricflow_values, run, same, semantic_manifest

# Compiling the analysis also writes target/semantic_manifest.json, which lists the metrics.
run(["dbt", "compile", "--select", "metric_values", "--quiet"])
names = [metric["name"] for metric in semantic_manifest()["metrics"]]

# MetricFlow: every metric in one query, grouped by the source every mart shares.
from_metricflow = metricflow_values(names, ["source"])

# The plain SQL, as dbt compiled it.
sql = open("target/compiled/fellstrike/analyses/metric_values.sql", encoding="utf-8").read()
with psycopg.connect(os.environ["WAREHOUSE_URL"]) as conn:
    from_sql = {(name, source): value for source, name, value in conn.execute(sql)}

# A source with no rows in a mart (no real exposures yet) comes back from MetricFlow as an empty cell and is missing
# from the SQL. Both mean the same, so empty cells only count when the SQL has the metric.
problems = []
for key in sorted(set(from_metricflow) | set(from_sql)):
    if key not in from_sql:
        if from_metricflow[key] is not None:
            problems.append(f"{key[0]} ({key[1]}): MetricFlow has {from_metricflow[key]}, the SQL has nothing")
    elif key not in from_metricflow:
        problems.append(f"{key[0]} ({key[1]}): the SQL has it, MetricFlow does not")
    elif not same(from_metricflow[key], from_sql[key]):
        problems.append(f"{key[0]} ({key[1]}): MetricFlow {from_metricflow[key]}, SQL {from_sql[key]}")

print("\n".join(problems) if problems else
      f"All {len(from_sql)} values match: {len(names)} metrics, by source, from MetricFlow and from plain SQL.")
sys.exit(1 if problems else 0)
