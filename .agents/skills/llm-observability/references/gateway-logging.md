# Gateway logging, metrics and spend (LiteLLM)

> Verified against LiteLLM v1.105.0 docs (proxy Prometheus, logging, config settings, cost tracking) and source, 2026-10-11

## What it is and when to choose it

The gateway is where the user-facing path is measured: every client request, every key and team, every backend. LiteLLM Proxy exposes Prometheus metrics, writes per-request spend logs to Postgres, and forwards request logs/traces to callbacks (Langfuse, OpenTelemetry, S3, and others). If you run LiteLLM (see the `llm-gateway` skill), make it your primary SLO and cost signal; engine metrics explain the causes.

## Install

Prometheus metrics are part of the open-source proxy; enable the callback:

```yaml
litellm_settings:
  callbacks: ["prometheus"]
```

Restart the proxy, then check (key from env, never echoed):

```bash
curl -fsS -H "Authorization: Bearer $LITELLM_API_KEY" http://localhost:4000/metrics | grep -E '^litellm_' | cut -d'{' -f1 | sort -u | head
```

Only the managed batch/file metrics are documented as Enterprise.

## Minimal working config

A privacy-first baseline: metrics on, labels trimmed, content off, spend logs bounded.

```yaml
litellm_settings:
  callbacks: ["prometheus"]
  prometheus_exclude_labels: # drop PII / high-cardinality labels everywhere
    - user_email
    - client_ip
    - user_agent
    - end_user
  turn_off_message_logging: true # no prompts/responses to logging callbacks
  redact_user_api_key_info: true # strip key/user info from logging callbacks
  global_disable_no_log_param: false # true = clients cannot opt out of logging with no-log

general_settings:
  store_prompts_in_spend_logs: false # default; keep it
  maximum_spend_logs_retention_period: "30d" # default null = never purged
  maximum_spend_logs_retention_interval: "1d"
```

`prometheus_exclude_labels` and `prometheus_exclude_metrics` are validated at startup (unknown names fail fast) and always win over `prometheus_metrics_config`. Use the include-based `prometheus_metrics_config` (groups of `metrics` + `include_labels`) when you want an explicit allowlist instead.

## How it plugs into the stack

### `/metrics` access

- Proxy port (default 4000) `/metrics` requires a LiteLLM key since v1.85.0. Scrape with a dedicated key via Prometheus `authorization.credentials_file`. `require_auth_for_metrics_endpoint: false` (under `litellm_settings`) turns this off; only do that on a private network.
- `--prometheus_metrics_port 4001` (or `PROMETHEUS_METRICS_PORT`, v1.101.0+) serves the same metrics from a separate process **without** key auth, bound to the proxy `--host`. Keep it off public ingress.
- Multiple workers: set `PROMETHEUS_MULTIPROC_DIR` to a writable directory so metrics aggregate across workers.

### Metrics that matter

Counters appear in exposition with a `_total` suffix (e.g. `litellm_proxy_total_requests_metric_total`); histograms with `_bucket`/`_sum`/`_count`. Confirm names against your `/metrics` output.

| Question                 | Metric                                                                                                                                          | Notes                                                                            |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Request volume           | `litellm_proxy_total_requests_metric`                                                                                                           | labels incl. `requested_model`, `status_code`, `route`, `team`, key hash/alias   |
| Failures                 | `litellm_proxy_failed_requests_metric`                                                                                                          | `exception_status`, `exception_class`                                            |
| End-to-end latency (SLO) | `litellm_request_total_latency_metric`                                                                                                          | histogram; arrival → end of processing                                           |
| Upstream latency         | `litellm_llm_api_latency_metric`                                                                                                                | backend call only                                                                |
| TTFT                     | `litellm_llm_api_time_to_first_token_metric`                                                                                                    | streaming requests only                                                          |
| Gateway wait             | `litellm_request_queue_time_seconds`, `litellm_in_flight_requests`                                                                              | overloaded proxy vs slow backend                                                 |
| Tokens                   | `litellm_input_tokens_metric`, `litellm_output_tokens_metric`, `litellm_total_tokens_metric`                                                    | plus cached/reasoning token breakdowns                                           |
| Spend                    | `litellm_spend_metric`                                                                                                                          | USD, by key/team/model                                                           |
| Backend health           | `litellm_deployment_state` (0 healthy, 1 partial outage, 2 outage), `litellm_deployment_failure_responses`, `litellm_deployment_total_requests` | per `litellm_model_name`, `api_base`                                             |
| Budgets                  | `litellm_remaining_team_budget_metric`, `litellm_remaining_api_key_budget_metric`, …                                                            | `prometheus_initialize_budget_metrics: true` emits them for idle keys/teams too  |
| Pricing gaps             | `litellm_zero_cost_requests_total`                                                                                                              | `reason`: `missing_pricing_key`, `pricing_not_applied`, `cost_calculation_error` |
| Logging health           | `litellm_callback_logging_failures_metric`                                                                                                      | failed deliveries to Langfuse, S3, …                                             |

Example queries:

```promql
# error ratio per model (5m)
sum by (requested_model) (rate(litellm_proxy_failed_requests_metric_total[5m]))
  / sum by (requested_model) (rate(litellm_proxy_total_requests_metric_total[5m]))
# p95 end-to-end latency per model group
histogram_quantile(0.95, sum by (model_group, le) (rate(litellm_request_total_latency_metric_bucket[5m])))
# spend per team per hour
sum by (team_alias) (increase(litellm_spend_metric_total[1h]))
```

`end_user` is not tracked on Prometheus by default (cardinality); `enable_end_user_cost_tracking_prometheus_only: true` turns it on, with caps `prometheus_end_user_metrics_max_series_per_metric` and `prometheus_end_user_metrics_ttl_seconds`.

### Logging callbacks

```yaml
litellm_settings:
  callbacks: ["prometheus", "otel"] # or "langfuse_otel" (needs LITELLM_OTEL_V2=true)
  turn_off_message_logging: true
callback_settings:
  otel:
    message_logging: false
```

- OTel: env `OTEL_EXPORTER` (`otlp_http`, `otlp_grpc`, `console`), `OTEL_ENDPOINT`, `OTEL_HEADERS`.
- Langfuse: `callbacks: ["langfuse_otel"]` plus `LITELLM_OTEL_V2=true` in the proxy env (read once at startup, so restart the proxy; OTel v2 replaces the v1 `otel` integration, pick one) (or `["otel"]` pointed at a Collector). Keys, hosts, classic-callback and per-team details: see the Langfuse note below.
- Keep secrets in env/secret store, never in the YAML committed to git.

**Langfuse in this stack.** Use the `langfuse_otel` preset (needs `LITELLM_OTEL_V2=true`) so gateway generations carry model, usage, cost and key/team attribution; keep `turn_off_message_logging: true` until content logging is approved.

Depth: install the langfuse skill (npx skills add ScaleDockHQ/llm-skills --skill langfuse)

### Spend logs

Each request writes a row to `LiteLLM_SpendLogs` (Postgres): key, team, user, model, tokens, spend, timings, metadata. Prompts and responses are only stored if `store_prompts_in_spend_logs: true`.

- `disable_spend_logs: true` stops writing rows (budgets still work from counters; you lose per-request history).
- `disable_error_logs: true` stops storing error records in the DB.
- Retention: `maximum_spend_logs_retention_period` (e.g. `"30d"`; default null disables cleanup), `maximum_spend_logs_retention_interval` (how often cleanup runs, default `1d`).
- APIs: `GET /spend/logs` (legacy, truncates to the 10,000 most recent matches), `GET /spend/logs/v2` (paginated, `page_size` up to 1000), `/global/spend/report` (Enterprise) for grouped reports.

```bash
curl -fsS -H "Authorization: Bearer $LITELLM_API_KEY" \
  "http://localhost:4000/spend/logs/v2?start_date=2026-10-01%2000:00:00&end_date=2026-10-02%2000:00:00&page=1&page_size=100" \
  | jq '.data | length'
```

## Operating

- After changing labels or callbacks, check series count (`count({__name__=~"litellm_.*"})`) and Prometheus head series.
- Alert on `litellm_callback_logging_failures_metric` growth if audit logging is mandatory.
- Rotate the scrape key like any other key; it only needs to read `/metrics`.

## Tuning knobs worth knowing

- `prometheus_emit_stream_label: true`: adds a `stream` label to request metrics.
- `prometheus_metrics_config`: per-group `include_labels` allowlist.
- Per-request controls: `no-log: true` in the request body skips logging for that request (disable with `global_disable_no_log_param: true`); header `x-litellm-disable-callbacks: <name>` (Enterprise) disables named callbacks; header `x-litellm-enable-message-redaction: true` redacts content for one request.
- `LiteLLM-Disable-Message-Redaction: true` request header **overrides** `turn_off_message_logging` for that request, so any client can opt into content logging. Account for this in the privacy review (see `privacy.md`).

## Known pitfalls

- **PII in metric labels by default**: `user_email`, `client_ip`, `user_agent`, `end_user` appear on several metrics. Exclude them unless you need them, and remember Prometheus retention applies to labels too.
- **Spend shows $0** for self-hosted models without pricing; see `cost-tracking.md` and watch `litellm_zero_cost_requests_total`.
- **Unbounded spend log table**: no retention by default; the table grows with every request.
- **Dashboards built on base names** miss the `_total` suffix and show "No data".
- **Dedicated metrics port exposed** publicly leaks key aliases, teams and spend.
- **`turn_off_message_logging` does not cover spend logs**; that is `store_prompts_in_spend_logs`.

## Official links

- LiteLLM Prometheus: https://docs.litellm.ai/docs/proxy/prometheus
- LiteLLM logging and callbacks: https://docs.litellm.ai/docs/proxy/logging
- LiteLLM config settings: https://docs.litellm.ai/docs/proxy/config_settings
- LiteLLM cost tracking / spend: https://docs.litellm.ai/docs/proxy/cost_tracking
- LiteLLM repo: https://github.com/BerriAI/litellm
