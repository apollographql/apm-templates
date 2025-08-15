# Datadog Dashboard Template

This folder contains a ready-to-import Datadog dashboard template for Apollo GraphOS Router v2 along
with a recommended Router telemetry configuration that powers the widgets in the dashboard.

## Prerequisites

- Datadog account with permissions to import dashboards
- Router telemetry data is flowing to Datadog:
  - Datadog OpenTelemetry (OTLP) integration enabled in Datadog
  - Apollo Router v2 running with telemetry exporters set up to export traces and metrics to an OTLP
    endpoint.
  - Datadog Agent or OTel-Collector set up to receive traces and metrics from the Router and send to
    Datadog.
- Access to edit your Router config (router.yaml) to add telemetry instrumentation

## Best practices

- Use the dashboard as a starting point for your own customizations.
- Keep an eye on cardinality; avoid highly dynamic attributes on metrics when possible. We have done
  this by default in the router telemetry config below.
- Implement trace sampling if you have a large traffic volume.

## Import the dashboard into Datadog (recommended first)

1. Sign in to Datadog
2. Open the file [graphos-template.json](./graphos-template.json), copy all contents
3. In Datadog UI navigate to Dashboards > New Dashboard > Create a Dashboard w/ any name
4. Paste the JSON into the dashboard by simply clicking in an empty space on the newly created
   dashboard and (`Cmd+V` or `Ctrl+V`) and then confirm
5. The dashboard will appear under your Dashboards list

## Apollo Router v2 telemetry configuration

After you import the dashboard, apply the telemetry configuration below to your Apollo Router
(router.yaml) so that all dashboard widgets populate with data.

- If you already have telemetry configured, merge these settings into your existing file.
- Prefer the simplest path? Replace your telemetry section with the one below.

```yaml
telemetry:
  instrumentation:
    # OTel span attributes you will see:
    #    - HTTP server span attributes: https://opentelemetry.io/docs/specs/semconv/http/http-spans/#http-server-span
    #    - HTTP client span attributes: https://opentelemetry.io/docs/specs/semconv/http/http-spans/#http-client-span
    #    - GraphQL server span attributes: https://opentelemetry.io/docs/specs/semconv/graphql/graphql-spans/
    spans: # https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/spans
      default_attribute_requirement_level: recommended # change to "required" for less data https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/spans#default_attribute_requirement_level

      router: # Apollo specific attribute options: https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/standard-attributes#router
        attributes:
          otel.name: router
          operation.name: "router"
          resource.name:
            request_method: true # or replace with <operation_name : string> to see the operation name of the graphql request in the APM UI but be weary of trace metrics. This could result in high cardinality metrics on the resource_name attribute. ex: avg:trace.router{*} by {resource_name}

      supergraph: # Apollo specific attribute options: https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/standard-attributes#supergraph
        attributes:
          otel.name: supergraph
          operation.name: "taco"
          resource.name:
            operation_name: string
          otel.status_code:  # This attribute will be set to true if the response from the router contained errors in the response body and will mark spans as Error in the APM UI.
            static: ERROR
            condition:
              eq:
                - true
                - on_graphql_error: true
          otel.status_description:
            response_errors: $[0].extensions.code
          error.message:
            response_errors: $[0].message
          graphql.errors:
            on_graphql_error: true

      subgraph: # Apollo specific attribute options: https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/standard-attributes#subgraph
        attributes:
          otel.name: subgraph
          operation.name: "subgraph"
          resource.name:
            subgraph_operation_name: string
          otel.status_code:  # This attribute will be set to true if the response from the subgraph contained errors in the response body and will mark spans as Error in the APM UI.
            static: ERROR
            condition:
              eq:
                - true
                - subgraph_on_graphql_error: true
          otel.status_description:
            subgraph_response_errors: $[0].extensions.code
          graphql.errors:
            subgraph_on_graphql_error: true
          # Datadog Error Tracking attributes to populate spans with graphql response error data in the APM UI: error.*
          error.message:
            subgraph_response_errors: $[0].message
          error.stack:
            subgraph_response_errors: $[0].extensions.stacktrace


      # OTel metrics and attributes you will see:
      #    - HTTP Server metrics: https://opentelemetry.io/docs/specs/semconv/http/http-metrics/#http-server
      #    - HTTP Client metrics: https://opentelemetry.io/docs/specs/semconv/http/http-metrics/#http-client
    instruments: # https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/instruments
      default_attribute_requirement_level: required # change to "recommended" for more data https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/instruments#default_requirement_level
      
      router:
        http.server.request.duration: # https://opentelemetry.io/docs/specs/semconv/http/http-metrics/#metric-httpserverrequestduration
          attributes:
            graphql.errors: # This attribute will be set to true if the response from the router contained errors in the response body
              on_graphql_error: true
              
      subgraph:
        http.client.request.duration: # https://opentelemetry.io/docs/specs/semconv/http/http-metrics/#metric-httpclientrequestduration
          attributes:
            subgraph.name: true
            http.response.status_code:
              subgraph_response_status: code # https://www.apollographql.com/docs/graphos/routing/observability/telemetry/instrumentation/selectors#subgraph
            graphql.errors: # This attribute will be set to true if the response from the subgraph contained errors in the response body
              subgraph_on_graphql_error: true

      connector:
        http.client.request.body.size:
          attributes:
            connector.source.name: true
            subgraph.name: true
        http.client.request.duration:
          attributes:
            connector.source.name: true
            subgraph.name: true
            http.response.status_code:
              connector_http_response_status: code
        http.client.response.body.size:
          attributes:
            connector.source.name: true
            subgraph.name: true
```

## Next steps

- Confirm data is flowing by opening the imported dashboard in Datadog.
- If some widgets remain empty, verify that:
  - Router is running v2 and telemetry is enabled
  - Traces and metrics reach Datadog
  - Attributes used by the dashboard (e.g., otel.name, graphql.errors, subgraph.name) exist in your
    spans/metrics
  - You are filtering by the correct service name, env, and version in the dashboard.

If you find issues or have suggestions, please open a pull request or issue in this repository.
