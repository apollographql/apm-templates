#!/usr/bin/env python3
"""Validate Dynatrace dashboard templates.

Checks Grail files against the real Dynatrace dashboard document schema
(derived from genuine exports in Dynatrace's public GitHub repos) and scans
all files for known bad patterns introduced by the Datadog conversion.

Usage: python3 dynatrace/scripts/validate-dashboards.py [file ...]
Exits non-zero if any ERROR-level finding remains.
"""

import json
import re
import sys
from pathlib import Path

DYNATRACE_DIR = Path(__file__).resolve().parent.parent

GRAIL_FILES = [
    "dashboard-template-grail.json",
    "dashboard-template-grail-configurable.json",
    "mcp-server-template-grail.json",
]
CLASSIC_FILES = [
    "dashboard-template.json",
    "mcp-server-template.json",
]

# Valid values per Dynatrace's dt-app-dashboards tiles.md
VALID_VISUALIZATIONS = {
    "lineChart", "areaChart", "barChart", "categoricalBarChart", "pieChart",
    "donutChart", "singleValue", "meterBar", "gauge", "table", "raw",
    "recordList", "histogram", "honeycomb", "heatmap", "scatterplot",
    "bandChart", "choroplethMap", "dotMap", "connectionMap", "bubbleMap",
}

# Datadog-agent metric names that do not exist in Dynatrace / OTel
DATADOG_METRICS = [
    "kubernetes.cpu.usage.total", "kubernetes.cpu.limits",
    "kubernetes.memory.usage", "kubernetes.memory.limits",
    "docker.cpu.usage", "docker.cpu.limit",
    "docker.mem.in_use", "docker.mem.limit",
    "system.cpu.stolen", "system.cpu.iowait", "system.cpu.system",
    "system.cpu.user", "system.cpu.idle", "system.mem.used", "system.mem.total",
]

# Datadog tag names whose OTLP equivalents differ
DATADOG_DIMENSIONS = {
    "`host`": "host.name",
    "`pod_name`": "k8s.pod.name",
    "`container_id`": "container.id",
}

# Attribute known to be wrong (correct: coprocessor.succeeded)
BAD_ATTRIBUTES = ["coprocessor.returned_an_error"]

# OTel counter (Sum) metrics: count() on these is always wrong — use sum()
COUNTER_METRICS = [
    "apollo.mcp.tool.count", "apollo.mcp.operation.count",
    "apollo.mcp.initialize.count", "apollo.mcp.get_info.count",
    "apollo.mcp.list_tools.count",
    "apollo.router.operations.coprocessor",
    "apollo.router.skipped.event.count",
    "apollo.router.lifecycle.license",
]


class Report:
    def __init__(self, path):
        self.path = path
        self.errors = []
        self.warnings = []

    def error(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)

    def dump(self):
        print(f"\n=== {self.path.name} ===")
        for e in self.errors:
            print(f"  ERROR   {e}")
        for w in self.warnings:
            print(f"  WARNING {w}")
        if not self.errors and not self.warnings:
            print("  OK")


def check_grail_schema(doc, rep):
    for key in ("version", "variables", "tiles", "layouts"):
        if key not in doc:
            rep.error(f"missing top-level key '{key}'")
    tiles = doc.get("tiles", {})
    layouts = doc.get("layouts", {})

    if set(tiles) != set(layouts):
        rep.error(
            f"tiles/layouts key mismatch: only-in-tiles={sorted(set(tiles) - set(layouts))} "
            f"only-in-layouts={sorted(set(layouts) - set(tiles))}"
        )
    for k, lay in layouts.items():
        if not {"x", "y", "w", "h"} <= set(lay):
            rep.error(f"layout {k} missing x/y/w/h")

    for k, t in tiles.items():
        ttype = t.get("type")
        if ttype == "data":
            if "visualizationType" in t:
                rep.error(f"tile {k} ('{t.get('title', '')}'): invented field "
                          f"'visualizationType' — must be 'visualization'")
            viz = t.get("visualization")
            if viz is None:
                if "visualizationType" not in t:
                    rep.warn(f"tile {k}: data tile has no 'visualization' (falls back to default)")
            elif viz not in VALID_VISUALIZATIONS:
                rep.error(f"tile {k}: invalid visualization '{viz}'")
            elif viz == "barChart":
                q = t.get("query", "")
                # barChart requires a time axis; summarize-by-category output has none
                if "summarize" in q and "timestamp" not in q.split("summarize", 1)[1]:
                    rep.error(f"tile {k}: barChart on categorical (summarize) query — "
                              f"use categoricalBarChart")
            if not t.get("query"):
                rep.error(f"tile {k}: data tile with empty query")
        elif ttype == "markdown":
            if "title" in t:
                rep.warn(f"tile {k}: markdown tile carries 'title' (genuine exports never do)")
            if "content" not in t:
                rep.error(f"tile {k}: markdown tile without content")
        else:
            rep.error(f"tile {k}: unknown tile type '{ttype}'")

    for v in doc.get("variables", []):
        missing = {"key", "type", "version"} - set(v)
        if missing:
            rep.error(f"variable '{v.get('key', '?')}': missing fields {sorted(missing)}")
        if v.get("multiple"):
            # multi-select must be referenced as in(field, array($key))
            pat_eq = re.compile(r"==\s*\$" + re.escape(v.get("key", "")))
            bad = [k for k, t in tiles.items()
                   if t.get("type") == "data" and pat_eq.search(t.get("query", ""))]
            if bad:
                rep.error(f"variable '{v['key']}' is multiple:true but tiles {bad[:5]}... "
                          f"use '== ${v['key']}' — needs in(field, array(${v['key']})) "
                          f"or multiple:false")


def check_grail_queries(doc, rep):
    for k, t in doc.get("tiles", {}).items():
        if t.get("type") != "data":
            continue
        q = t.get("query", "")
        title = t.get("title", "")
        label = f"tile {k} ('{title}')"

        for m in re.finditer(r"\bcount\(`(?:custom:)?([^`]+)`", q):
            metric = m.group(1)
            if metric in COUNTER_METRICS:
                rep.error(f"{label}: count() on counter metric '{metric}' — use sum()")
            else:
                rep.warn(f"{label}: count() on '{metric}' — returns observation count "
                         f"only if metric metadata supports it; verify in tenant "
                         f"(fallback: collector extract_count_metric -> *_count)")
        for m in re.finditer(r"percentile\([^)]*rollup:\s*avg[^)]*\)", q):
            rep.error(f"{label}: percentile(..., rollup: avg) averages series means — "
                      f"drop the rollup parameter")
        # fieldsAdd arithmetic on timeseries fields must use [] element-wise ops
        for m in re.finditer(r"fieldsAdd\s+\w+\s*=\s*([^|]+)", q):
            expr = m.group(1)
            idents = re.findall(r"\b([a-z_][a-z0-9_]*)\b(?!\s*\()", expr)
            idents = [i for i in idents if i not in ("array",)]
            if idents and "[]" not in expr and re.search(r"[+\-*/]", expr):
                rep.error(f"{label}: fieldsAdd arithmetic without []: '{expr.strip()[:60]}' — "
                          f"timeseries math needs a[]/b[] element-wise operators")
        for dd in DATADOG_METRICS:
            if f"`{dd}`" in q or f"`custom:{dd}`" in q:
                rep.error(f"{label}: Datadog-agent metric '{dd}' does not exist in Dynatrace")
        for dd, otel in DATADOG_DIMENSIONS.items():
            if re.search(r"by:\s*\{[^}]*" + re.escape(dd), q):
                rep.error(f"{label}: Datadog dimension {dd} — OTLP name is '{otel}'")
        if re.search(r"`custom:", q):
            rep.error(f"{label}: 'custom:' prefix inside DQL — Classic-only convention")
        for attr in BAD_ATTRIBUTES:
            if attr in q:
                rep.error(f"{label}: attribute '{attr}' does not exist — "
                          f"use coprocessor.succeeded")
        if re.search(r'service\.name\s*==\s*"(apollo-)?router"', q):
            rep.warn(f"{label}: hardcoded service.name — should use $service_name variable")

        # title/query consistency for percentile levels
        for m in re.finditer(r"[pP](\d{2})\b", title):
            lvl = m.group(1)
            if "percentile" in q and f"percentile(`" in q and lvl not in re.findall(r"percentile\([^,]+,\s*(\d+)", q):
                rep.warn(f"{label}: title says p{lvl} but query computes "
                         f"percentile {re.findall(r'percentile\([^,]+,\s*(\d+)', q)}")


def check_classic(doc, rep):
    text = json.dumps(doc)
    for dd in DATADOG_METRICS:
        if f"custom:{dd}" in text or f'"{dd}"' in text:
            rep.error(f"Datadog-agent metric '{dd}' does not exist in Dynatrace")
    for attr in BAD_ATTRIBUTES:
        if attr in text:
            rep.error(f"attribute '{attr}' does not exist — use coprocessor.succeeded")
    for tile in doc.get("tiles", []):
        name = tile.get("name", "")
        if "Non-2xx" in name:
            crit = json.dumps(tile.get("queriesSettings", {})) + json.dumps(tile)
            if "status_code" not in crit.replace(name, ""):
                rep.error(f"tile '{name}': no status-code filter — shows ALL responses")


def main():
    args = [Path(a) for a in sys.argv[1:]]
    if not args:
        args = [DYNATRACE_DIR / f for f in GRAIL_FILES + CLASSIC_FILES]

    failed = False
    for path in args:
        rep = Report(path)
        try:
            doc = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            rep.error(f"cannot parse: {e}")
            rep.dump()
            failed = True
            continue

        if "tiles" in doc and isinstance(doc["tiles"], dict):
            check_grail_schema(doc, rep)
            check_grail_queries(doc, rep)
        else:
            check_classic(doc, rep)
        rep.dump()
        failed = failed or bool(rep.errors)

    print(f"\n{'FAILED' if failed else 'PASSED'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
