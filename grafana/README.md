# WIP: Apollo Router Grafana Dashboard Example

> Note: This is the first draft of a Grafana template. It has not had the same iterations as the
> other templates.

![example dashboard preview](./dashboard-preview.png)

This repository contains a [JSON file](./dashboard-template.json) containing an example
[Grafana](https://grafana.com/oss/grafana/) dashboard for reference or use with the Apollo Router.

**The code in this repository is experimental and has been provided for reference purposes only.
Community feedback is welcome but this project may not be supported in the same way that
repositories in the official [Apollo GraphQL GitHub organization](https://github.com/apollographql)
are. If you need help you can file an issue on this repository,
[contact Apollo](https://www.apollographql.com/contact-sales) to talk to an expert, or create a
ticket directly in Apollo Studio.**

## Installation

This repository contains the JSON needed to
[import as a new dashboard](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/import-dashboards/)
in your Grafana instance.

### Dashboard Requirements

This dashboard requires:

- Grafana
- A Prometheus datasource
- Prometheus gathering metrics from the Apollo Router running v2.0 or higher

This dashboard also leverages the following telemetry configuration for the router:

```yaml
telemetry:
  instrumentation:
    instruments:
      # Use "required" (Apollo's recommended default) to attach required attributes to standard
      # instruments by default. "recommended" includes experimental attributes from OpenTelemetry's
      # development-status conventions (e.g., graphql.document, subgraph.graphql.document), which
      # can create high cardinality and may contain sensitive information. See:
      # https://www.apollographql.com/docs/graphos/routing/observability/router-telemetry-otel/enabling-telemetry/instruments#default_requirement_level
      default_requirement_level: required
      router:
        http.server.request.duration:
          attributes:
            graphql.operation.name:
              operation_name: string
            graphql.errors:
              on_graphql_error: true
        http.server.request.body.size: true
        http.server.response.body.size: true
        http.server.active_requests: true
      subgraph:
        http.client.request.duration:
          attributes:
            subgraph.name: true
        http.client.request.body.size:
          attributes:
            subgraph.name: true
        http.client.response.body.size: true
```

### Usage

Once imported, select your datasource in the top variable section and the dashboard should populate
so long as you use the standard metric values.

Dashboard variables:

- `otel_scope_name` - Filter by OpenTelemetry scope name (default: "apollo/router")
