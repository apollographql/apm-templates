#!/usr/bin/env python3
"""Generate *-summary variants of the Grail dashboard templates.

The DQL `timeseries percentile()` function requires histogram buckets, which
Dynatrace only stores for tenants on the DPS "Metrics powered by Grail" rate
card. On any other tenant every percentile tile fails with:

    timeseries percentile function requires a rollup with the given metric key(s).

This script derives summary-statistics variants (avg/min/max — always
available) from the percentile-based templates:

    dashboard-template-grail.json              -> dashboard-template-grail-summary.json
    dashboard-template-grail-configurable.json -> dashboard-template-grail-configurable-summary.json
    mcp-server-template-grail.json             -> mcp-server-template-grail-summary.json

The percentile templates remain the source of truth: edit those, then re-run
this script and the validator.

Usage: python3 dynatrace/scripts/generate-summary-variants.py
"""

import json
import re
import sys
from pathlib import Path

DYNATRACE_DIR = Path(__file__).resolve().parent.parent

SOURCE_FILES = [
    "dashboard-template-grail.json",
    "dashboard-template-grail-configurable.json",
    "mcp-server-template-grail.json",
]

TITLE_MAP = [
    ("Request Duration Percentiles", "Request Duration (Avg / Min / Max)"),
    ("P95 Latency by Subgraph", "Avg Latency by Subgraph"),
    ("Query Planning Duration Percentiles and Wait Time",
     "Query Planning Duration (Avg) and Wait Time"),
    ("Query Parsing Duration Percentiles and Wait Time",
     "Query Parsing Duration (Avg) and Wait Time"),
    ("& p95 Latency", "& Avg Latency"),
    ("p90 duration of call_tool", "avg duration of call_tool"),
    ("p90 duration of graphql operations", "avg duration of graphql operations"),
    ("p99 HTTP server duration", "avg HTTP server duration"),
]

# Markdown explainers rewritten for the summary variants (matched by prefix).
SUMMARY_PCTL_EXPLAINER = (
    "**Summary-statistics variant**\n\n"
    "This dashboard uses avg/min/max instead of percentiles because the DQL "
    "`timeseries percentile()` function requires the DPS **Metrics powered by "
    "Grail** rate card (histogram buckets are not stored without it).\n\n"
    "- Avg — the mean request duration. Rising averages indicate broad "
    "slowdowns (subgraph latency, query planning, or load), but hide tail "
    "behavior: a small share of very slow requests barely moves the mean.\n"
    "- Max — the slowest observed request. Isolated spikes are usually "
    "harmless one-offs; frequent or sustained high max values point to heavy "
    "queries, retries, or transient infrastructure problems.\n"
    "- Min — the fastest possible response, reflecting the Router's baseline "
    "overhead (parsing, validation, planning, middleware).\n\n"
    "**Caveats**\n\n"
    "- Without percentiles, tail latency regressions (p95/p99) are invisible "
    "here — watch Max and the error-rate charts, and consider upgrading to "
    "the Metrics powered by Grail rate card for true percentile tiles "
    "(the non-summary templates).")
CONTENT_MAP = [
    ("**How to interpret percentiles**", SUMMARY_PCTL_EXPLAINER),
]

# name = percentile(`metric`, N[, filter: ...])
NAMED_PCTL = re.compile(
    r"(\w+)\s*=\s*percentile\((`[^`]+`)\s*,\s*\d+((?:\s*,\s*filter:[^)]*)?)\)")
# bare percentile(`metric`, N) — no assignment, no filter argument
BARE_PCTL = re.compile(r"percentile\((`[^`]+`)\s*,\s*(\d+)\)")
SENTINEL = "\x00"


def avg_name(pctl_name):
    if re.fullmatch(r"[pP]\d+", pctl_name):
        return "Avg"
    return re.sub(r"p\d+", "avg", pctl_name)


def transform_query(query):
    """Replace percentile aggregations with avg. Returns (query, renames, deleted)."""
    renames = {}
    deleted = []

    # Group named percentile assignments by (metric, filter) so p50/p95/p99 of
    # the same series collapse into a single avg.
    groups = {}
    for m in NAMED_PCTL.finditer(query):
        filt = m.group(3).strip().lstrip(",").strip()
        groups.setdefault((m.group(2), filt), []).append(m)

    replacements = {}  # match.span -> replacement text
    for (metric, filt), matches in groups.items():
        filt_part = f", {filt}" if filt else ""
        has_avg = f"avg({metric}{filt_part})" in query
        for i, m in enumerate(matches):
            if not has_avg and i == 0:
                new = avg_name(m.group(1))
                renames[m.group(1)] = new
                replacements[m.span()] = f"{new} = avg({metric}{filt_part})"
            else:
                deleted.append(m.group(1))
                replacements[m.span()] = SENTINEL

    out, last = [], 0
    for (start, end), text in sorted(replacements.items()):
        out.append(query[last:start])
        out.append(text)
        last = end
    out.append(query[last:])
    query = "".join(out)

    # Drop deleted assignments along with one adjoining comma.
    query = re.sub(r"\s*" + SENTINEL + r"\s*,", "", query)
    query = re.sub(r",\s*" + SENTINEL, "", query)
    query = query.replace(SENTINEL, "")

    # Bare percentile (no assignment): identifier changes with it.
    for m in BARE_PCTL.finditer(query):
        metric_plain = m.group(1).strip("`")
        renames[f"percentile({metric_plain}, {m.group(2)})"] = f"avg({metric_plain})"
    query = BARE_PCTL.sub(r"avg(\1)", query)

    # Rewrite references to renamed series in later pipeline stages.
    for old, new in renames.items():
        if re.fullmatch(r"\w+", old):
            query = re.sub(rf"\b{old}\b", new, query)

    return query, renames, deleted


def rename_strings(node, renames):
    if isinstance(node, dict):
        return {k: rename_strings(v, renames) for k, v in node.items()}
    if isinstance(node, list):
        return [rename_strings(v, renames) for v in node]
    if isinstance(node, str):
        return renames.get(node, node)
    return node


def transform_tile(tile):
    if tile.get("type") == "markdown":
        for prefix, replacement in CONTENT_MAP:
            if tile.get("content", "").startswith(prefix):
                tile = dict(tile, content=replacement)
        return tile
    if tile.get("type") != "data" or "percentile(" not in tile.get("query", ""):
        return tile
    tile = json.loads(json.dumps(tile))  # deep copy
    tile["query"], renames, deleted = transform_query(tile["query"])
    for old, new in TITLE_MAP:
        if old in tile.get("title", ""):
            tile["title"] = tile["title"].replace(old, new)
    if "visualizationSettings" in tile:
        vs = rename_strings(tile["visualizationSettings"], renames)
        if isinstance(vs.get("unitsOverrides"), list):
            vs["unitsOverrides"] = [o for o in vs["unitsOverrides"]
                                    if o.get("identifier") not in deleted]
        tile["visualizationSettings"] = vs
    return tile


def main():
    failed = False
    for name in SOURCE_FILES:
        src = DYNATRACE_DIR / name
        dst = DYNATRACE_DIR / (src.stem + "-summary.json")
        doc = json.loads(src.read_text())
        doc["tiles"] = {k: transform_tile(t) for k, t in doc.get("tiles", {}).items()}
        leftovers = [k for k, t in doc["tiles"].items()
                     if "percentile(" in t.get("query", "")]
        if leftovers:
            print(f"ERROR {dst.name}: percentile() still present in tiles {leftovers}")
            failed = True
        dst.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {dst.name}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
