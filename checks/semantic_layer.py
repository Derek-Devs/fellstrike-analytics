"""Shared by the scripts in checks/: reads the semantic layer's metrics and asks MetricFlow for their numbers.

The scripts run from the dbt folder with the environment active, and this module loads ../.env for them.
"""
import csv
import json
import math
import os
import subprocess
import sys
import tempfile

from dotenv import load_dotenv

# The warehouse's settings, for the scripts and for the dbt and mf commands they run.
load_dotenv("../.env")


def run(command):
    """Runs a dbt or mf command and stops with its output if it fails."""
    done = subprocess.run(command, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(f"{' '.join(command)} failed:\n{done.stdout}\n{done.stderr}")


def number(value):
    """A value as a float, or None when it is empty (a ratio over zero, or no rows)."""
    return None if value in ("", None) else float(value)


def same(a, b):
    if a is None or b is None:
        return a is None and b is None
    return math.isclose(float(a), float(b), rel_tol=1e-9, abs_tol=1e-9)


def semantic_manifest():
    """The metrics and semantic models dbt last parsed (run dbt parse or dbt compile first)."""
    return json.load(open("target/semantic_manifest.json", encoding="utf-8"))


def semantic_model_of(manifest, name):
    """The mart a metric reads. A ratio or derived metric reads the mart of its first input."""
    metric = next(m for m in manifest["metrics"] if m["name"] == name)
    params = metric["type_params"]
    if params["metric_aggregation_params"]:
        return params["metric_aggregation_params"]["semantic_model"]
    first_input = params["numerator"] or params["metrics"][0]
    return semantic_model_of(manifest, first_input["name"])


def metricflow_values(names, group_by):
    """Every metric in names from one mf query, grouped by the group_by items.

    Returns {(metric, group values...): number}. Times are cut to the day (2026-09-07), so other tools can match them.
    """
    values = {}
    with tempfile.TemporaryDirectory() as folder:
        out = os.path.join(folder, "metrics.csv")
        run(["mf", "query", "--metrics", ",".join(names), "--group-by", ",".join(group_by), "--csv", out])
        with open(out, encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                group = tuple(row[g][:10] if g.startswith("metric_time") else row[g] for g in group_by)
                for name in names:
                    values[(name, *group)] = number(row[name])
    return values
