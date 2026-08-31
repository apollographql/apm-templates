#!/usr/bin/env node
/**
 * Converts Datadog dashboard JSON to Dynatrace Classic dashboard JSON.
 * Usage: node convert-datadog-to-dynatrace.js [path-to-datadog-dashboard.json]
 * Reads from datadog/dashboard-template.json by default, writes to ../dashboard-template.json
 */

const fs = require('fs');
const path = require('path');

const COL_WIDTH = 152;
const ROW_HEIGHT = 50;

function parseDatadogQuery(q) {
  if (!q || typeof q !== 'string') return { metric: 'custom:unknown', spaceAggregation: 'AVG', splitBy: [] };
  // e.g. count:http.server.request.duration{$service,$env}.as_count()
  // p99:http.server.request.duration{...}
  // sum:apollo.mcp.tool.count{...} by {apollo.mcp.tool_name}.as_count()
  const aggMatch = q.match(/^(count|sum|avg|min|max|p99|p95|p90|median):([a-zA-Z0-9._]+)\{/);
  const metric = aggMatch ? aggMatch[2] : 'unknown';
  let spaceAggregation = 'AVG';
  if (aggMatch) {
    const a = aggMatch[1];
    if (a === 'count' || a === 'sum') spaceAggregation = a === 'count' ? 'COUNT' : 'SUM';
    else if (a === 'avg') spaceAggregation = 'AVG';
    else if (a === 'min' || a === 'max') spaceAggregation = a.toUpperCase();
    else if (a === 'p99') spaceAggregation = 'PERCENTILE_90';
    else if (a === 'p95' || a === 'p90') spaceAggregation = 'PERCENTILE_90';
    else if (a === 'median') spaceAggregation = 'MEDIAN';
  }
  const byMatch = q.match(/by\s+\{([^}]+)\}/);
  const splitBy = byMatch ? byMatch[1].split(',').map((s) => s.trim()) : [];
  return { metric: `custom:${metric}`, spaceAggregation, splitBy };
}

function getFirstMetricQuery(def) {
  const req = def.requests && def.requests[0];
  if (!req) return null;
  const queries = req.queries || (req.query ? [req.query] : []);
  const q = queries[0];
  return q && (q.query || q);
}

function flattenWidgets(widgets, baseX = 0, baseY = 0) {
  const out = [];
  for (const w of widgets) {
    const def = w.definition || w;
    const layout = w.layout || { x: 0, y: 0, width: 12, height: 1 };
    const x = baseX + (layout.x || 0);
    const y = baseY + (layout.y || 0);
    const width = layout.width || 12;
    const height = layout.height || 1;

    if (def.type === 'group' && def.widgets) {
      out.push(...flattenWidgets(def.widgets, x, y));
      continue;
    }
    if (def.type === 'split_group') {
      const source = def.source_widget_definition;
      if (source && source.requests && source.requests[0]) {
        const q = source.requests[0].query && source.requests[0].query.query;
        const parsed = parseDatadogQuery(q);
        const dim = source.split_config && source.split_config.split_dimensions && source.split_config.split_dimensions[0];
        if (dim && dim.one_graph_per) parsed.splitBy = [dim.one_graph_per];
        out.push({
          type: 'distribution',
          def: { ...source, _splitBy: parsed.splitBy, _parsed: parsed },
          layout: { x, y, width, height },
        });
      }
      continue;
    }

    out.push({
      type: def.type,
      def,
      layout: { x, y, width, height },
    });
  }
  return out;
}

function toBounds(layout) {
  return {
    left: (layout.x || 0) * COL_WIDTH,
    top: (layout.y || 0) * ROW_HEIGHT,
    width: (layout.width || 12) * COL_WIDTH,
    height: (layout.height || 1) * ROW_HEIGHT,
  };
}

function buildDataExplorerTile(name, parsed, displayType, queryId = 'A') {
  const seriesType = displayType === 'bars' ? 'COLUMN' : 'LINE';
  return {
    name,
    tileType: 'DATA_EXPLORER',
    configured: true,
    tileFilter: {},
    customName: name,
    queries: [
      {
        id: queryId,
        metric: parsed.metric,
        timeAggregation: 'DEFAULT',
        spaceAggregation: parsed.spaceAggregation,
        splitBy: parsed.splitBy || [],
        filterBy: { filterOperator: 'AND', nestedFilters: [], criteria: [] },
        limit: 100,
        enabled: true,
      },
    ],
    queriesSettings: { resolution: '' },
    visualConfig: {
      type: 'GRAPH_CHART',
      global: { hideLegend: false, seriesType },
      rules: [
        {
          matcher: queryId + ':',
          valueFormat: 'auto',
          properties: { color: 'DEFAULT', seriesType },
          seriesOverrides: [],
        },
      ],
      axes: {
        xAxis: { displayName: '', visible: true },
        yAxes: [
          {
            displayName: '',
            visible: true,
            min: 'AUTO',
            max: 'AUTO',
            position: 'LEFT',
            queryIds: [queryId],
            defaultAxis: true,
          },
        ],
      },
      graphChartSettings: { connectNulls: true },
    },
    metricExpressions: [],
  };
}

function convertTile(flat) {
  const bounds = toBounds(flat.layout);
  const def = flat.def;
  const title = def.title || '';

  if (flat.type === 'note') {
    return {
      name: title || 'Note',
      tileType: 'MARKDOWN',
      configured: true,
      bounds,
      tileFilter: {},
      markdown: def.content || '',
    };
  }

  if (flat.type === 'timeseries') {
    const req = def.requests && def.requests[0];
    const displayType = (req && req.display_type) || 'line';
    let parsed = { metric: 'custom:unknown', spaceAggregation: 'AVG', splitBy: [] };
    const q = getFirstMetricQuery(def);
    if (q) parsed = parseDatadogQuery(q);
    const tile = buildDataExplorerTile(title || 'Timeseries', parsed, displayType);
    tile.bounds = bounds;
    return tile;
  }

  if (flat.type === 'distribution') {
    const req = def.requests && def.requests[0];
    const q = req && req.query && req.query.query;
    const parsed = def._parsed || parseDatadogQuery(q);
    const tile = buildDataExplorerTile(title || 'Distribution', parsed, 'line');
    tile.bounds = bounds;
    return tile;
  }

  if (flat.type === 'scatterplot') {
    return {
      name: title || 'Scatter plot',
      tileType: 'MARKDOWN',
      configured: true,
      bounds,
      tileFilter: {},
      markdown: `*Scatter plot: ${title}*\n\nDynatrace Data Explorer does not provide a direct scatter plot equivalent. Recreate this in Data Explorer or use the Datadog template for this visualization.`,
    };
  }

  if (flat.type === 'query_table') {
    const q = getFirstMetricQuery(def);
    const parsed = parseDatadogQuery(q);
    const tile = {
      name: title || 'Table',
      tileType: 'DATA_EXPLORER',
      configured: true,
      bounds,
      tileFilter: {},
      customName: title || 'Table',
      queries: [
        {
          id: 'A',
          metric: parsed.metric,
          timeAggregation: 'DEFAULT',
          spaceAggregation: parsed.spaceAggregation,
          splitBy: parsed.splitBy || [],
          filterBy: { filterOperator: 'AND', nestedFilters: [], criteria: [] },
          limit: 100,
          enabled: true,
        },
      ],
      queriesSettings: { resolution: '' },
      visualConfig: {
        type: 'TABLE',
        rules: [{ matcher: 'A:', valueFormat: 'auto', properties: {}, seriesOverrides: [] }],
        tableSettings: { isThresholdBackgroundAppliedToCell: false },
      },
      metricExpressions: [],
    };
    return tile;
  }

  return null;
}

function main() {
  const inputPath =
    process.argv[2] ||
    path.join(__dirname, '../../datadog/dashboard-template.json');
  const outputPath = path.join(__dirname, '../dashboard-template.json');

  const raw = fs.readFileSync(inputPath, 'utf8');
  const datadog = JSON.parse(raw);

  const flat = flattenWidgets(datadog.widgets || []);
  const tiles = [];
  for (const f of flat) {
    const tile = convertTile(f);
    if (tile) tiles.push(tile);
  }

  const dashboard = {
    dashboardMetadata: {
      name: (datadog.title || 'GraphOS Runtime').replace(/\s*Template\s*$/, '') + ' (Dynatrace)',
      owner: 'apm-templates',
      shared: true,
      dynamicFilters: {
        filters: ['SERVICE_TAG_KEY:service', 'CUSTOM_DIMENSION:env', 'CUSTOM_DIMENSION:version'],
        genericTagFilters: [],
      },
    },
    tiles,
  };

  fs.writeFileSync(outputPath, JSON.stringify(dashboard, null, 2), 'utf8');
  console.log('Wrote', outputPath, 'with', tiles.length, 'tiles');
}

main();
