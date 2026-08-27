# Dynatrace Dashboard Templates

This folder contains Dynatrace dashboard templates for monitoring Apollo GraphOS Runtime and Apollo
MCP Server when telemetry is sent to Dynatrace via OTLP.

The templates are experimental. Align tag and dimension names with how you send OTLP telemetry to
Dynatrace, and verify metric keys match those present in your environment.

## Choosing a template

Pick along three axes: **which dashboard** (GraphOS Runtime vs. MCP Server), **which Dynatrace
format** (Grail vs. Classic — determined by your environment URL), and for Grail, **whether your
tenant has the DPS "Metrics powered by Grail" rate card** (required for true percentile tiles;
without it use a `*-summary` variant — see
[Prerequisites](#metrics-powered-by-grail-rate-card-required-for-percentile-tiles)).

| Template                                                       | Dashboard       | Format                         | Latency tiles                      | Service filter                                                   |
| -------------------------------------------------------------- | --------------- | ------------------------------ | ---------------------------------- | ---------------------------------------------------------------- |
| `dashboard-template-grail-configurable.json` **(recommended)** | GraphOS Runtime | Grail (`apps.dynatrace.com`)   | true p90/p95/p99 (needs rate card) | `$service_name` variable, plus scatter-plot performance profiles |
| `dashboard-template-grail-configurable-summary.json`           | GraphOS Runtime | Grail                          | avg/min/max only                   | `$service_name` variable, plus scatter-plot performance profiles |
| `dashboard-template-grail.json`                                | GraphOS Runtime | Grail                          | true p90/p95/p99 (needs rate card) | none (no dashboard variables)                                    |
| `dashboard-template-grail-summary.json`                        | GraphOS Runtime | Grail                          | avg/min/max only                   | none                                                             |
| `mcp-server-template-grail.json`                               | MCP Server      | Grail                          | true p90/p99 (needs rate card)     | `$service_name` variable                                         |
| `mcp-server-template-grail-summary.json`                       | MCP Server      | Grail                          | avg/min/max only                   | `$service_name` variable                                         |
| `dashboard-template.json`                                      | GraphOS Runtime | Classic (`live.dynatrace.com`) | p90 (Data Explorer maximum)        | Classic dynamic filters                                          |
| `mcp-server-template.json`                                     | MCP Server      | Classic                        | p90 (Data Explorer maximum)        | Classic dynamic filters                                          |

In short: environment URL `apps.dynatrace.com` → Grail; `live.dynatrace.com` → Classic. On Grail,
take the base template if your tenant has the Metrics powered by Grail rate card, the `*-summary`
variant if not (the percentile error _"timeseries percentile function requires a rollup..."_ on
import means you need the summary variant). Prefer the `-configurable` runtime dashboard unless you
specifically want no dashboard variables.

## Contents

### Grail format (`apps.dynatrace.com` / Document API)

- **dashboard-template-grail.json** – GraphOS Runtime dashboard (no dashboard filters).
- **dashboard-template-grail-configurable.json** – Same dashboard with a `$service_name` filter
  variable wired into all service-scoped tiles, plus scatter-plot performance-profile tiles.
  **Recommended variant.**
- **mcp-server-template-grail.json** – Apollo MCP Server dashboard with a `$service_name` filter
  variable.
- **\*-summary.json** (`dashboard-template-grail-summary.json`,
  `dashboard-template-grail-configurable-summary.json`, `mcp-server-template-grail-summary.json`) –
  Generated variants for tenants **without** the DPS "Metrics powered by Grail" rate card: every
  `percentile()` tile is replaced with avg/min/max summary statistics (see
  [Prerequisites](#metrics-powered-by-grail-rate-card-required-for-percentile-tiles)). Do not edit
  by hand — edit the base template and re-run `scripts/generate-summary-variants.py`.

### Classic format (Dashboards Classic / `live.dynatrace.com`)

- **dashboard-template.json** – GraphOS Runtime dashboard.
- **mcp-server-template.json** – Apollo MCP Server dashboard.

### Scripts

- **scripts/validate-dashboards.py** – Validates all templates: Grail document-schema conformance
  and known bad-pattern checks (run after any edit).
- **scripts/generate-summary-variants.py** – Regenerates the `*-summary.json` variants from the
  Grail base templates (run after editing any base template, then re-validate).
- **scripts/convert-datadog-to-dynatrace.js**, **scripts/convert-classic-to-grail.py** – Historical
  conversion scripts used to bootstrap these templates from the Datadog template. **Do not re-run
  them**: the JSON files have since been hand-corrected extensively and regeneration would
  reintroduce known bugs.

## Prerequisites

### Delta temporality (required)

Dynatrace OTLP ingest **only accepts delta temporality** and silently drops cumulative histograms.
Apollo Router's OTLP exporter defaults to cumulative, so every histogram-based tile (request
duration, latency percentiles, body sizes) will be empty unless you configure:

```yaml
telemetry:
  exporters:
    metrics:
      otlp:
        temporality: delta
```

For other OTel SDKs (e.g. around MCP Server), set
`OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta`.

### Metrics powered by Grail rate card (required for percentile tiles)

The DQL `timeseries percentile()` function used by the latency p90/p95/p99 tiles is
[only available to DPS customers with the **Metrics powered by Grail** rate card](https://docs.dynatrace.com/docs/analyze-explore-automate/metrics/histograms).
Without it, Dynatrace stores histograms as min/max/sum/count summaries (buckets are discarded), and
every percentile tile fails with _"timeseries percentile function requires a rollup with the given
metric key(s)"_ — no query rewrite can recover percentiles from summary data. Delta temporality and
explicit-bucket histograms (the Router's default) are correct as configured above; only the rate
card unlocks bucket storage and percentile queries. If your environment cannot get this rate card,
use the generated **`*-summary.json`** template variants, which replace every percentile tile with
avg/min/max summary statistics. Note also that OpenTelemetry _exponential_ histograms are never
stored with buckets — only explicit-bucket histograms support percentiles.

### Telemetry in Dynatrace

Router and/or MCP Server metrics must be arriving in Dynatrace (OTLP exporter to a Dynatrace
ActiveGate/collector endpoint or the ingest API). Ensure resource attributes such as `service.name`,
`service.version`, and `deployment.environment` are sent so dashboard filters apply.

### Span ingestion (one tile)

The Grail runtime dashboard's **"GraphQL Errors by Subgraph"** tile queries **spans**
(`fetch spans`), not metrics. It requires router trace export into Dynatrace. All other tiles are
metrics-only.

Note that trace ingest is scoped separately from metric ingest: an API token with only
`metrics.ingest` sends metrics fine while traces are silently rejected. The token used by the
router's OTLP trace exporter must also hold the **`openTelemetryTrace.ingest`** scope. To verify
auth quickly, an empty POST to `{env}/api/v2/otlp/v1/traces` with the token returns 200 when the
scope is present, 401/403 when it is not.

## Installation

> **Which template do I need?** See the [Choosing a template](#choosing-a-template) table at the
> top. Short version:
>
> - Environment URL `https://{id}.apps.dynatrace.com` → **Grail** (`-grail`) templates; add
>   `-summary` if your tenant lacks the Metrics powered by Grail rate card.
> - Environment URL `https://{id}.live.dynatrace.com` → **Classic** templates.

### Grail environments (`apps.dynatrace.com`)

1. **UI import** – In the **Dashboards** app, click **Upload** and select the template JSON.
2. **Document API** –
   `POST https://{your-environment-id}.apps.dynatrace.com/platform/document/v1/documents` with an
   OAuth client token holding the `document:documents:write` scope, or use the upload script with
   `--grail` (see below).

### Classic environments (`live.dynatrace.com`)

1. Go to **Dashboards Classic** and use the import function, or
   `POST https://{your-environment-id}.live.dynatrace.com/api/config/v1/dashboards` (omit `id`;
   Dynatrace assigns it), or use the upload script.

## Metric keys and filters

- **Grail templates** use bare OTLP metric names (e.g. `http.server.request.duration`,
  `apollo.mcp.tool.count`) — the names the Router and MCP Server export.
- **Classic templates** use the `custom:` prefix (e.g. `custom:http.server.request.duration`), which
  is the Metrics Classic convention for OTLP-ingested metrics, plus `builtin:` keys for the OneAgent
  host tiles. If your environment registers OTLP metrics under different keys, adjust in Data
  Explorer.
- **Grail filter variable**: `$service_name` (multi-select) is wired as
  `in(service.name, array($service_name))` in the configurable and MCP templates. Default values are
  `router` / `apollo-mcp-server`; adjust to your `service.name`.
- **Adding env/version filters (optional)**: add a variable (e.g. `environment`) in the Dashboards
  app and append `| filter in(deployment.environment, array($environment))` (or `service.version`
  for a version filter) to the tiles you want scoped. These are not pre-wired because attribute
  presence varies by setup — a filter on an absent attribute blanks the tile.
- **Classic filters**: template variables map to `dashboardMetadata.dynamicFilters`
  (`SERVICE_TAG_KEY:service`, `CUSTOM_DIMENSION:env`, `CUSTOM_DIMENSION:version`). Adjust keys to
  match your tags.

## Container/Host section

The infrastructure tiles come in four flavors — keep the rows matching your setup and delete the
rest:

| Tiles                         | Source                               | Metrics                                                                          |
| ----------------------------- | ------------------------------------ | -------------------------------------------------------------------------------- |
| Kubernetes CPU/Memory         | OTel Collector kubeletstats receiver | `k8s.pod.cpu.usage`, `k8s.pod.memory.usage`, `k8s.container.*_limit`             |
| Host CPU/Memory (Hostmetrics) | OTel Collector hostmetrics receiver  | `system.cpu.utilization`, `system.memory.usage` (split by `state`)               |
| Host CPU/Memory (OneAgent)    | Dynatrace OneAgent                   | `dt.host.cpu.usage`, `dt.host.memory.usage`                                      |
| Docker CPU/Memory             | OTel Collector docker stats receiver | `container.cpu.usage.total`, `container.memory.usage.total`, `container.*.limit` |

These tiles are intentionally not scoped by `$service_name` — host/container metrics do not carry
`service.name`.

## Known caveats (verify in your tenant)

- **Observation counts**: request/error/miss-count tiles use DQL `count(metric)` on histogram
  metrics. Depending on metric metadata, `count()` may return series cardinality instead of
  observation counts. If counts look implausibly flat (≈ number of instances), either verify the
  metric's metadata or use the OTel Collector's `extract_count_metric` transform
  ([Dynatrace docs](https://docs.dynatrace.com/docs/ingest-from/opentelemetry/collector/use-cases/histograms))
  and point the tiles at the derived `*_count` metrics.
- **Boolean attributes** (`graphql.errors`, `apollo.mcp.success`, `coprocessor.succeeded`,
  `subgraph.active_requests`) are compared as strings (`== "true"`). If your ingest preserves them
  differently, adjust the comparisons.
- **Span status** on the span-based tile is matched case-insensitively
  (`lower(toString(span.status_code)) == "error"`); confirm the field/value shape in your tenant.
- **Percentiles over tables**: the "Top Most Queried…" tables time-average per-slot p95 values — an
  approximation, since DQL cannot compute a whole-window percentile from `timeseries` output.

## Limitations — features not carried over from the Datadog template

These templates were derived from the [Datadog template](../datadog/dashboard-template.json). The
following Datadog features have **no equivalent** here; where noted, an alternative approach is
documented.

| Datadog feature                                                                                       | Status in Dynatrace templates                                                                                                                     | Alternative                                                                                      |
| ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Event overlays (schema-reload / cache-warmup bands on Query Planning, Cache, and Compute Jobs charts) | Not translatable — Grail dashboards have no chart-overlay concept                                                                                 | Correlate manually with deploy times, CI/CD events, or GraphOS launch history                    |
| Anomaly detection bands (`anomalies()` on throughput and success-rate charts)                         | Not translatable in dashboard tiles                                                                                                               | Configure Davis anomaly detectors / metric events in Dynatrace settings                          |
| Latency distribution (histogram) widgets                                                              | Converted to average-over-time line charts, retitled "… Duration (avg)"                                                                           | Open the metric in a Notebook for bucket/percentile analysis; percentile tiles cover the tail    |
| Small-multiples grids (per-subgraph / per-connector histogram panels with uniform y-axes)             | Replaced by "Top Most Queried…" ranked tables (top 12 by request count)                                                                           | Split further in a Notebook if per-entity charts are needed                                      |
| Dual y-axes (e.g. cache misses as bars + record count on a right log axis)                            | Single-axis multi-series charts with a computed `hit_rate_pct` field                                                                              | —                                                                                                |
| Log / sqrt / pow y-axis scales                                                                        | All charts are linear                                                                                                                             | Adjust axis settings in the dashboard UI after import if supported for your tile                 |
| Per-series styling (red dashed limit lines, stacked-area CPU states)                                  | Limit values are plain series (`cpu_limit`, `memory_limit`) alongside usage                                                                       | Restyle in the dashboard UI                                                                      |
| Legend column readouts (avg/min/max in the legend)                                                    | Not configured                                                                                                                                    | —                                                                                                |
| `$env` / `$version` template variables                                                                | Deliberately not wired (a filter on an absent attribute blanks the tile)                                                                          | See _Adding env/version filters_ above                                                           |
| Fixed 1-week comparison scatter plots                                                                 | Real `scatterplot` tiles with `from: now()-7d` in the **configurable** Grail template only; placeholders in the plain Grail and Classic templates | Use the configurable variant                                                                     |
| `trace_service` widget (MCP dashboard)                                                                | Markdown placeholder                                                                                                                              | Add a `SERVICE_VERSATILE` tile (Classic) or link the service screen if you have a service entity |
| p95/p99 percentiles in **Classic**                                                                    | Downgraded to p90 (`PERCENTILE_90` is the Data Explorer maximum); titles reflect this                                                             | Grail templates use true p95/p99                                                                 |
| Image/branding widget                                                                                 | Dropped                                                                                                                                           | —                                                                                                |
| MCP **gateway** dashboard (`datadog/mcp-gateway-template.json`)                                       | No Dynatrace counterpart exists in this repo                                                                                                      | —                                                                                                |
| 12-column grid layout                                                                                 | Converted to Grail/Classic layout coordinates                                                                                                     | Resize tiles after import as needed                                                              |

## Upload script

`utils/upload-dashboard.sh` supports both Classic and Grail environments. Copy `utils/.env.example`
to `utils/.env` and fill in the variables for your environment.

### Grail / Document API

```bash
cd dynatrace/utils
cp .env.example .env
# Edit .env: set DYNATRACE_ENV_ID, DYNATRACE_OAUTH_CLIENT_ID, DYNATRACE_OAUTH_CLIENT_SECRET
./upload-dashboard.sh ../dashboard-template-grail-configurable.json --grail
./upload-dashboard.sh ../mcp-server-template-grail.json --grail
```

**Getting Grail OAuth credentials:**

1. In `apps.dynatrace.com`, go to **Settings → Account Management → OAuth Clients**
2. Create a new OAuth client with scope `document:documents:write`
3. Copy the Client ID and Client Secret into `.env`

### Classic API

```bash
cd dynatrace/utils
cp .env.example .env
# Edit .env: set DYNATRACE_URL and DYNATRACE_API_TOKEN
./upload-dashboard.sh ../dashboard-template.json
./upload-dashboard.sh ../mcp-server-template.json
```

Validation (optional): for Classic, POST to `/api/config/v1/dashboards/validator` to check the
payload before creating. For all templates, run `python3 dynatrace/scripts/validate-dashboards.py`
after local edits.

For recommended Router telemetry configuration (instruments, attributes), see Apollo's observability
docs
([Router telemetry OTLP](https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel)).
