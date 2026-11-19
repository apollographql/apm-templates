# Datadog Dashboard Template

This folder contains:

- A ready-to-import Datadog dashboard template for Apollo GraphOS Router v2.
- A sample MCP Gateway and server template for Apollo MCP runtime. This template has not had the
  same iterations as the other templates.

The complete documentation on how to utilize this template including the recommended Router
configuration can be found in Apollo's
[Datadog Integration Documentation](https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/apm-guides/datadog)

## Apollo MCP Server template

`mcp-server-template.json` works with Apollo MCP Server v2.2.0 or later. After you import it, set
the `service` and `env` template variables to your server's values.

The **MCP Requests** group uses `mcp.server.operation.duration`, which follows the OpenTelemetry MCP
semantic conventions. Those conventions are experimental, so a minor release can rename the metric
or its attributes. The **Authentication** group only has data when the server uses OAuth.

The template expects these settings:

- **Delta temporality.** Set `telemetry.exporters.metrics.otlp.temporality` to `delta`. With the
  default, cumulative, Datadog drops the first point of each new series, so the count widgets
  undercount rare tools, rare errors, and every pod that starts.
- **Histograms as distributions.** The latency widgets use percentiles, which need the Datadog Agent
  to map OTLP histograms to distributions. This is the Agent's default.
- **`parent_based_sampler: false`, for the APM widget.** With the default, `true`, the server skips
  tracing any request whose caller sends trace flags `00`, so APM hits miss those requests. The
  metric widgets count every request either way.
