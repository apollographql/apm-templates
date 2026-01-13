## Apollo GraphOS Runtime APM Templates

This repository hosts the documentation and template artifacts to aid in setting up an APM solution
that monitors your Apollo GraphOS Runtime deployment.

Each template is provided within a subdirectory matching the name of its APM provider. Detailed
instructions for each provider can be found in the README of said subdirectories.

**The code in this repository is experimental and may be subject to change based on feedback
received during the experimental period. Given that, all feedback is welcome. If you need help or
have suggestions or feedback, please file an issue on this repository.**

### Dashboard Section Coverage

The following table shows which dashboard sections are available in each template. The Datadog template serves as the reference model, and other templates are compared against it.

| Dashboard Section | Datadog | Grafana | New Relic |
|-------------------|---------|---------|-----------|
| **Request Traffic & Health: Client → Router** | ✅ | ✅ | ✅ |
| - Volume of Requests Per Status Code | ✅ | ✅ | ✅ |
| - Throughput (Requests per Second) | ✅ | ✅ | ✅ |
| - Error Rate Percent | ✅ | ✅ | ✅ |
| - GraphQL Errors by Operation | ✅ | ✅ | ✅ |
| **Request Characteristics: Client → Router** | ✅ | ✅ | ✅ |
| - Request Body Size (p99 / Max) | ✅ | ✅ | ✅ |
| **Request Performance & Latency: Client → Router** | ✅ | ✅ | ✅ |
| - Request Duration Distribution (Histogram) | ✅ | ✅ | ✅ |
| - Request Duration Percentiles (p90, p95, p99, min, max) | ✅ | ✅ | ✅ |
| **Request Traffic & Health: Router → Backend** | ✅ | ✅ | ✅ |
| - HTTP Requests by Subgraph/Connector | ✅ | ✅ | ✅ |
| - Throughput (Requests per Second) | ✅ | ✅ | ✅ |
| - Non-2xx Responses | ✅ | ✅  | ✅ |
| **Request Characteristics: Router → Backend** | ✅ | ❌ | ✅ |
| - Response Body Size | ✅ | ❌ | ✅ |
| **Request Performance & Latency: Router → Backend** | ✅ | ✅ | ✅ |
| - P95 Latency by Subgraph | ✅ | ✅ | ✅ |
| - P95 Latency by Operation Name | ❌ | ✅ | ✅ |
| - GraphQL Errors by Subgraph | ✅ | ✅ | ✅ |
| - Request Duration Distribution (Histogram) | ✅ | ✅ | ✅ |
| - Subgraph Performance Profile (Scatter Plot) | ✅ | ❌ | ✅ |
| - Connector Source Performance Profile (Scatter Plot) | ✅ | ❌ | ✅ |
| **Top Most Queried Subgraphs: Request Duration Distributions** | ✅ | ✅ | ✅ |
| **Top Most Queried Connector Sources: Request Duration Distributions** | ✅ | ✅ | ✅ |
| **Query Planning** | ✅ | ✅ | ✅ |
| - Duration and Wait Time | ✅ | ✅ | ✅ |
| - Evaluated Plans | ✅ | ✅ | ✅ |
| **Cache** | ✅ | ✅ | ✅ |
| - Misses vs. Record Count | ✅ | ✅ | ✅ |
| - Cache Hit Percentage | ✅ | ✅ | ✅ |
| - Record Counts by Instance | ✅ | ✅ | ✅ |
| - Record Counts by Type | ✅ | ✅ | ✅ |
| - Misses by Type | ✅ | ✅ | ✅ |
| - Hit % by Instance | ✅ | ✅ | ✅ |
| **Compute Jobs** | ✅ | ✅ | ✅ |
| - Query Planning Duration Percentiles and Wait Time | ✅ | ✅ | ✅ |
| - Query Parsing Duration Percentiles and Wait Time | ✅ | ✅ | ✅ |
| - Queued Jobs | ✅ | ✅ | ✅ |
| - Job Counts by Outcome | ✅ | ✅ | ✅ |
| **Container/Host Resource Monitoring** | ✅ | ✅ | ✅ |
| - Kubernetes CPU Usage | ✅ | ✅ | ✅ |
| - Kubernetes Memory Usage | ✅ | ✅ | ✅ |
| - Host CPU/Memory Usage (OTEL Collector) | ✅ | ❌ | ✅ |
| - Docker CPU/Memory Usage | ✅ | ❌ | ✅ |
| **Coprocessors** | ✅ | ✅ | ✅ |
| - Request Duration | ✅ | ✅ | ✅ |
| - Request Count | ✅ | ✅ | ✅ |
| - Success Rate | ✅ | ✅ | ✅ |
| **Sentinel Metrics** | ✅ | ❌ | ✅ |
| - Uplink and Licensing | ✅ | ❌ | ✅ |
| - Open Connections by Schema and Launch ID | ✅ | ❌ | ✅ |
| - Router Relative Overhead | ✅ | ❌ | ✅ |
| **Entity Caching** | ❌ | ❌ | ✅ |
| **Uplink (Dedicated Page)** | ❌ | ❌ | ✅ |

**Legend:**
- ✅ = Section/feature is present
- ❌ = Section/feature is not present

**Notes:**
- **Grafana**: Refers to `grafana/graphos-template.json` - focuses on core metrics for essential monitoring
- **New Relic**: Organized into dashboard pages rather than sections, but covers equivalent functionality
- Some sections may have different names or organizational structures across platforms but provide equivalent monitoring capabilities

### Naming Differences Across Templates

While the templates cover similar functionality, there are some naming differences across platforms. The following table maps equivalent chart/section names:

| Datadog | Grafana | New Relic | Notes |
|---------|---------|-----------|-------|
| GraphQL Errors by Operation | GraphQL Errors by Operation | GraphQL Errors by Operation (Placeholder) | |
| GraphQL Errors by Subgraph | GraphQL Errors by Subgraph | GraphQL Errors by Subgraph | |
| Http Requests by Status Code | Http Requests by Subgraph | Request Rate by Status Code<br>Request Rate by Subgraph | Grafana groups by subgraph instead of status code; New Relic splits into separate charts |
| P95 Latency By Operation Name | P95 Latency By Operation Name | x | |
| P95 Latency by Connector Source | x | P95 Latency by Connector Source | |
| Subgraph Performance Profile (Dashboard Time Scale)<br>Subgraph Performance Profile (One Week Fixed Time Scale) | x | Subgraph Performance Profile (RPS vs P95 Latency) | Datadog has two versions with different time scales; New Relic has one combined version |
| Connector Source Performance Profile (Dashboard Time Scale)<br>Connector Source Performance Profile (One Week Fixed Time Scale) | x | x | |
| Subgraph Request Volume | Subgraph Request Volume | Request Rate by Subgraph | Different naming (volume vs rate) but equivalent functionality |
| Container/Host | x | Infrastructure<br>Resources | New Relic splits into two separate pages |
| Request Performance & Latency: Router → Backend | Request Performance & Latency: Router → Backend | Request Performance | New Relic uses shorter page name |
| Request Traffic & Health: Client → Router | Request Traffic & Health: Client → Router | Overview | New Relic uses generic "Overview" page name |
| Query Planning | Query Planning | Query Planning & Cache | New Relic combines query planning and cache on one page |
| Cache | Cache | Query Planning & Cache | New Relic combines with query planning |
| Compute Jobs | x | Query Planning & Cache (subset) | New Relic includes compute jobs within query planning page |
| Uplink and Licensing | x | Uplink | New Relic has dedicated Uplink page with shorter name |
| Router Request Rate | x | Router Request Rate | |
| Router Request Latency | x | Router Request Latency | |
| GraphQL Request Error Rate | x | GraphQL Request Error Rate | |
| Error Codes | x | Error Codes | |
| Request Latency with P99 | x | Request Latency with P99 | |
| Subgraph Latency P99 | x | Subgraph Latency P99 | |
| Overall Coprocessor Latency | x | Overall Coprocessor Latency | |
| Coprocessor Latency (p95) by Stage | x | Coprocessor Latency (p95) by Stage | |
| Entity Cache Hits by Type | x | Entity Cache Hits by Type | |
| Entity Cache Hits by Subgraph | x | Entity Cache Hits by Subgraph | |
| Overall Uplink Latency | x | Overall Uplink Latency | |
| p95 Uplink Latency by Kind | x | p95 Uplink Latency by Kind | |
| Percent Uplink Failure | x | Percent Uplink Failure | |

**Key Observations:**
- **Datadog** and **Grafana** generally use similar naming conventions with section prefixes (e.g., "Request Traffic & Health: Client → Router")
- **New Relic** uses shorter, more concise names and organizes content into dashboard pages rather than nested sections
- **New Relic** includes additional descriptive subtitles for some charts (e.g., "Subgraph Performance Profile (RPS vs P95 Latency)")
- Some charts are **New Relic-specific** and don't have direct equivalents in other templates
- **Percentile notation** varies: Datadog/Grafana use "p99", New Relic uses "P99" or includes it in parentheses
- **New Relic** combines related sections (e.g., "Query Planning & Cache") while others keep them separate
- ✅ **Standardized naming**: Several naming differences have been standardized to match the Datadog template as the base reference

### Development

This repository uses [`mise`](https://mise.jdx.dev/) to manage tooling and tasks. Currently, these
are just markdown linting and spell-checking. After installing it, run `mise trust` and then
`mise install` to install the tools. To verify your commit will pass PR checks before pushing, run
`mise pr-all`. Any errors can be fixed with `mise fix-spelling` or `mise format-markdown`.
