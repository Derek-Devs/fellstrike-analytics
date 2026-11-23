"""Checks that Lightdash and MetricFlow give the same number for every metric (docs/analytics-design.md, section 9.4).

Lightdash reads MetricFlow's definitions but writes its own SQL, so the two engines could drift. This asks both for
every metric by source, and by week and source, and lists any value that differs or that only one side has. It exits
with 1 when there is one.

Run it from analytics/dbt, with the environment active and Lightdash running:
    python ..\\checks\\lightdash_matches_metricflow.py
It needs LIGHTDASH_API_KEY and LIGHTDASH_PROJECT in analytics/.env.
"""
import json
import os
import sys
import time
import urllib.request

from semantic_layer import metricflow_values, number, run, same, semantic_manifest, semantic_model_of

LIGHTDASH = "http://localhost:8080"
PROJECT = os.environ["LIGHTDASH_PROJECT"]
HEADERS = {"Authorization": f"ApiKey {os.environ['LIGHTDASH_API_KEY']}", "Content-Type": "application/json"}


def lightdash(method, path, body=None):
    """Calls Lightdash's API and returns its results."""
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(LIGHTDASH + path, data=data, headers=HEADERS, method=method)
    with urllib.request.urlopen(request) as response:
        return json.load(response)["results"]


def lightdash_rows(explore, dimensions, metrics):
    """Runs one query on an explore and waits for its rows. Lightdash runs queries in the background."""
    source = f"{explore}_source"
    query = {
        "exploreName": explore,
        "dimensions": dimensions,
        "metrics": metrics,
        # Both sources, said out loud: each table's required filter would otherwise start at simulated.
        "filters": {"dimensions": {"id": "sources", "and": [
            {"id": "source", "target": {"fieldId": source}, "operator": "equals", "values": ["real", "simulated"]},
        ]}},
        "sorts": [],
        "limit": 5000,
        "tableCalculations": [],
    }
    started = lightdash("POST", f"/api/v2/projects/{PROJECT}/query/metric-query", {"query": query})
    for _ in range(120):
        # 2,500 rows is the most a page can hold. The biggest query here returns a few dozen.
        page = lightdash("GET", f"/api/v2/projects/{PROJECT}/query/{started['queryUuid']}?page=1&pageSize=2500")
        if page["status"] == "ready":
            return page["rows"]
        if page["status"] in ("error", "cancelled", "expired"):
            sys.exit(f"Lightdash query on {explore} ended with {page['status']}: {page.get('error')}")
        time.sleep(0.5)
    sys.exit(f"Lightdash query on {explore} did not finish")


run(["dbt", "parse", "--quiet"])
manifest = semantic_manifest()
names = [metric["name"] for metric in manifest["metrics"]]
time_dimension = {sm["name"]: sm["defaults"]["agg_time_dimension"] for sm in manifest["semantic_models"]
                  if sm["defaults"] and sm["defaults"].get("agg_time_dimension")}
by_model = {}
for name in names:
    by_model.setdefault(semantic_model_of(manifest, name), []).append(name)

problems, compared = [], 0
for grain in (["source"], ["metric_time__week", "source"]):
    from_metricflow = metricflow_values(names, grain)
    from_lightdash = {}
    for explore, metrics in sorted(by_model.items()):
        # MetricFlow's metric_time__week is the mart's own time dimension cut to the week, which Lightdash names
        # <explore>_<column>_week.
        week = f"{explore}_{time_dimension[explore]}_week"
        dimensions = [f"{explore}_source"] if grain == ["source"] else [week, f"{explore}_source"]
        for row in lightdash_rows(explore, dimensions, [f"{explore}_{m}" for m in metrics]):
            group = tuple(str(row[d]["value"]["raw"])[:10] if d == week else row[d]["value"]["raw"]
                          for d in dimensions)
            for m in metrics:
                from_lightdash[(m, *group)] = number(row[f"{explore}_{m}"]["value"]["raw"])

    # MetricFlow joins every mart's results into one table, so a week one mart has no rows in comes back as an empty
    # cell. Lightdash has no row there at all. Both mean nothing happened.
    for key in sorted(set(from_metricflow) | set(from_lightdash), key=str):
        mf, ld = from_metricflow.get(key), from_lightdash.get(key)
        if key not in from_lightdash and mf is None:
            continue
        compared += 1
        if key not in from_lightdash:
            problems.append(f"{key}: MetricFlow has {mf}, Lightdash has no row")
        elif key not in from_metricflow:
            problems.append(f"{key}: Lightdash has {ld}, MetricFlow has no row")
        elif not same(mf, ld):
            problems.append(f"{key}: MetricFlow {mf}, Lightdash {ld}")

print("\n".join(problems[:40]) if problems else
      f"All {compared} values match: {len(names)} metrics, by source and by week and source, "
      "from MetricFlow and from Lightdash.")
if len(problems) > 40:
    print(f"... and {len(problems) - 40} more")
sys.exit(1 if problems else 0)
