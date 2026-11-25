"""Checks the charts and dashboards in lightdash/ before they are uploaded (docs/analytics-design.md, 9.3).

    python checks\\lightdash_content.py        (from this repository's root)

It fails when:
- a chart could add real and simulated numbers together: it must filter source to one value, or group by source so
  the two stay in separate rows
- a file names a person: an ownerEmail, or anything shaped like an email address (Lightdash's download adds the
  owner's email, so downloaded files are never committed as they come)
- a dashboard tile points at a chart that isn't in lightdash/charts/
"""
import pathlib
import re
import sys

import yaml

folder = pathlib.Path(__file__).resolve().parent.parent / "lightdash"
problems = []


def source_filters(chart):
    """The chart's filter rules on its explore's source column."""
    source = f"{chart['metricQuery']['exploreName']}_source"
    rules = (chart["metricQuery"].get("filters", {}).get("dimensions") or {}).get("and", [])
    return [rule for rule in rules if rule.get("target", {}).get("fieldId") == source], source


charts = {}
for path in sorted((folder / "charts").glob("*.yml")):
    chart = yaml.safe_load(path.read_text(encoding="utf-8"))
    charts[chart["slug"]] = path.name
    rules, source = source_filters(chart)
    one_source = any(rule["operator"] == "equals" and len(rule.get("values", [])) == 1 for rule in rules)
    split_by_source = source in chart["metricQuery"]["dimensions"]
    if not rules:
        problems.append(f"{path.name}: no filter on {source}")
    elif not (one_source or split_by_source):
        problems.append(f"{path.name}: filters {source} to more than one value without grouping by it")

for path in sorted((folder / "dashboards").glob("*.yml")):
    dashboard = yaml.safe_load(path.read_text(encoding="utf-8"))
    for tile in dashboard["tiles"]:
        slug = tile["properties"].get("chartSlug")
        if tile["type"] == "saved_chart" and slug not in charts:
            problems.append(f"{path.name}: tile {slug} has no chart in lightdash/charts/")

for path in sorted(folder.rglob("*.yml")):
    text = path.read_text(encoding="utf-8")
    if "ownerEmail" in text or re.search(r"[\w.+-]+@[\w-]+\.[\w.]+", text):
        problems.append(f"{path.relative_to(folder)}: holds an email address")

print("\n".join(problems) if problems else
      f"{len(charts)} charts and their dashboards are each tied to a source, and name nobody.")
sys.exit(1 if problems else 0)
