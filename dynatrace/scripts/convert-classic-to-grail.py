#!/usr/bin/env python3
"""
Convert Dynatrace Classic dashboard JSON templates to Dynatrace Grail (Document API) format.

Usage:
    python convert-classic-to-grail.py <source_file>

The output is the dashboard content JSON (version, variables, tiles, layouts),
suitable for UI import. Not wrapped in the Document API envelope.
"""

import json
import math
import sys
from typing import Any

# Grid constants: 1824px canvas / 24 columns = 76px per col; 50px per row unit
PX_PER_COL = 76
PX_PER_ROW = 50


def bounds_to_layout(bounds: dict) -> dict:
    """Convert classic pixel bounds to Grail grid layout units."""
    left = bounds.get("left", 0)
    top = bounds.get("top", 0)
    width = bounds.get("width", 912)
    height = bounds.get("height", 200)

    x = round(left / PX_PER_COL)
    w = round(width / PX_PER_COL)
    y = round(top / PX_PER_ROW)
    h = max(1, round(height / PX_PER_ROW))

    return {"x": x, "y": y, "w": w, "h": h}


SPACE_AGG_MAP = {
    "COUNT": "count",
    "AVG": "avg",
    "SUM": "sum",
    "MIN": "min",
    "MAX": "max",
    "PERCENTILE_90": "percentile90",
    "PERCENTILE_95": "percentile95",
    "PERCENTILE_99": "percentile99",
}

EVALUATOR_MAP = {
    "EQ": "==",
    "NE": "!=",
}


def agg_dql(space_agg: str, metric: str) -> str:
    """Return the DQL aggregation expression for a metric."""
    agg = SPACE_AGG_MAP.get(space_agg, "avg")
    if space_agg == "PERCENTILE_90":
        return f"percentile(`{metric}`, 90)"
    elif space_agg == "PERCENTILE_95":
        return f"percentile(`{metric}`, 95)"
    elif space_agg == "PERCENTILE_99":
        return f"percentile(`{metric}`, 99)"
    else:
        return f"{agg}(`{metric}`)"


def build_filter_clause(filter_by: dict) -> str:
    """Build a DQL filter clause from classic filterBy criteria."""
    criteria = filter_by.get("criteria", [])
    if not criteria:
        return ""

    conditions = []
    for c in criteria:
        dim_key = c.get("dimensionKey", "")
        evaluator = c.get("evaluator", "EQ")
        value = c.get("value", "")
        op = EVALUATOR_MAP.get(evaluator, "==")
        conditions.append(f'`{dim_key}` {op} "{value}"')

    if not conditions:
        return ""

    filter_op = filter_by.get("filterOperator", "AND")
    if filter_op == "AND":
        combined = " and ".join(conditions)
    else:
        combined = " or ".join(conditions)

    return f"| filter {combined}"


def build_split_by(split_by: list) -> str:
    """Build DQL by: clause from splitBy list."""
    if not split_by:
        return ""
    dims = ", ".join(f"`{d}`" for d in split_by)
    return f", by: {{{dims}}}"


def build_single_query_dql(query: dict) -> str:
    """Build a complete DQL timeseries query from a single classic query entry."""
    metric = query.get("metric", "")
    space_agg = query.get("spaceAggregation", "AVG")
    split_by = query.get("splitBy", [])
    filter_by = query.get("filterBy", {})

    agg_expr = agg_dql(space_agg, metric)
    by_clause = build_split_by(split_by)
    filter_clause = build_filter_clause(filter_by)

    dql = f"timeseries {agg_expr}{by_clause}"
    if filter_clause:
        dql += f"\n{filter_clause}"
    return dql


def get_alias_for_query(query_id: str, rules: list) -> str:
    """Extract alias for a query from visualConfig rules."""
    matcher = f"{query_id}:"
    for rule in rules:
        if rule.get("matcher") == matcher:
            alias = rule.get("properties", {}).get("alias", "")
            if alias:
                # Make alias a valid identifier: lowercase, replace spaces/special with underscore
                clean = alias.strip()
                # Replace non-alphanumeric/underscore chars with underscore
                result = ""
                for ch in clean:
                    if ch.isalnum() or ch == "_":
                        result += ch
                    else:
                        result += "_"
                # Strip leading digits
                if result and result[0].isdigit():
                    result = "_" + result
                if result:
                    return result
    return query_id.lower()


def build_multi_query_dql(queries: list, rules: list) -> str:
    """Build a multi-series DQL timeseries query block from multiple classic queries."""
    lines = []
    for q in queries:
        qid = q.get("id", "A")
        alias = get_alias_for_query(qid, rules)
        metric = q.get("metric", "")
        space_agg = q.get("spaceAggregation", "AVG")
        split_by = q.get("splitBy", [])
        filter_by = q.get("filterBy", {})

        agg_expr = agg_dql(space_agg, metric)
        by_clause = build_split_by(split_by)

        # Note: filters in multi-query blocks are appended after the timeseries block
        lines.append(f"  {alias} = {agg_expr}{by_clause}")

    dql = "timeseries {\n"
    dql += ",\n".join(lines)
    dql += "\n}"

    # Collect filter clauses (apply any that exist, per query — note multi-query
    # filters are tricky; we emit any non-empty filter from the first query that has one)
    filter_clauses = []
    for q in queries:
        fc = build_filter_clause(q.get("filterBy", {}))
        if fc and fc not in filter_clauses:
            filter_clauses.append(fc)

    for fc in filter_clauses:
        dql += f"\n{fc}"

    return dql


def get_visualization_type(visual_config: dict) -> str:
    """Map classic visualConfig type/seriesType to Grail visualizationType."""
    vis_type = visual_config.get("type", "GRAPH_CHART")
    series_type = visual_config.get("global", {}).get("seriesType", "LINE")

    if vis_type == "TABLE":
        return "table"
    elif vis_type == "SINGLE_VALUE":
        return "singleValue"
    elif vis_type == "GRAPH_CHART":
        if series_type == "COLUMN":
            return "bar"
        else:
            return "line"
    else:
        return "line"


def convert_markdown_tile(classic_tile: dict) -> dict:
    """Convert a classic MARKDOWN tile to Grail format."""
    return {
        "type": "markdown",
        "title": "",
        "content": classic_tile.get("markdown", ""),
    }


def convert_data_explorer_tile(classic_tile: dict) -> dict:
    """Convert a classic DATA_EXPLORER tile to Grail format."""
    title = classic_tile.get("customName", classic_tile.get("name", ""))
    queries = classic_tile.get("queries", [])
    visual_config = classic_tile.get("visualConfig", {})
    rules = visual_config.get("rules", [])
    vis_type = get_visualization_type(visual_config)

    # Filter to enabled queries only
    enabled_queries = [q for q in queries if q.get("enabled", True)]

    if not enabled_queries:
        return {
            "type": "data",
            "title": title,
            "query": "",
            "visualizationType": vis_type,
        }

    if len(enabled_queries) == 1:
        dql = build_single_query_dql(enabled_queries[0])
    else:
        dql = build_multi_query_dql(enabled_queries, rules)

    return {
        "type": "data",
        "title": title,
        "query": dql,
        "visualizationType": vis_type,
    }


def convert_classic_to_grail(classic: dict) -> dict:
    """Convert a full classic dashboard JSON to Grail dashboard content format."""
    tiles_dict = {}
    layouts_dict = {}

    classic_tiles = classic.get("tiles", [])

    idx = 0
    for tile in classic_tiles:
        tile_type = tile.get("tileType", "")
        bounds = tile.get("bounds", {"left": 0, "top": 0, "width": 912, "height": 200})

        if tile_type == "MARKDOWN":
            grail_tile = convert_markdown_tile(tile)
        elif tile_type == "DATA_EXPLORER":
            grail_tile = convert_data_explorer_tile(tile)
        else:
            # Skip unsupported tile types
            continue

        layout = bounds_to_layout(bounds)

        key = str(idx)
        tiles_dict[key] = grail_tile
        layouts_dict[key] = layout
        idx += 1

    return {
        "version": 13,
        "variables": [],
        "tiles": tiles_dict,
        "layouts": layouts_dict,
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: convert-classic-to-grail.py <source_file>", file=sys.stderr)
        sys.exit(1)

    source_path = sys.argv[1]

    with open(source_path, "r", encoding="utf-8") as f:
        classic = json.load(f)

    grail = convert_classic_to_grail(classic)

    print(json.dumps(grail, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
