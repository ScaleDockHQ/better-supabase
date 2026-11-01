# Alerting for LLM serving

> Verified against Prometheus v3.15.0 alerting-rule docs (rules validated with `promtool check rules`), metric names from vLLM v0.31.0, SGLang v0.5.21, llama.cpp, LiteLLM v1.105.0 and dcgm-exporter 4.8.4, 2026-10-11

## What it is and when to choose it

Prometheus evaluates alert rules and sends firing alerts to Alertmanager, which routes them to chat, email or a pager. For LLM serving the rule of thumb is: **page on what users feel, warn on what explains it**.

| Severity  | Fires on                      | Examples                                                                                                                                            |
| --------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `page`    | Symptoms (SLO breach)         | Gateway error ratio, p95 latency/TTFT over target, target down, all deployments of a model in outage                                                |
| `warning` | Causes and leading indicators | Requests queueing, KV cache near full, preemptions, GPU XID error, high GPU temperature, spend spike, logging callback failures, $0-priced requests |

## Install

Alert rules live in a file referenced by `rule_files` in `prometheus.yml`. Alertmanager is a separate binary/container (`prom/alertmanager`, port 9093) referenced under `alerting.alertmanagers`:

```yaml
rule_files:
  - alert-rules.yml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["node-b:9093"]
```

Validate before reload (Docker if `promtool` isn't installed):

```bash
docker run --rm --entrypoint promtool -v "$PWD:/w:ro" -w /w prom/prometheus:<tag> check rules alert-rules.yml
```

## Minimal working config

Start from `assets/alert-rules.yml`. Each rule has `alert`, `expr`, `for` (how long the condition must hold), optional `keep_firing_for`, `labels` (severity, routing) and `annotations` (summary, description, runbook link):

```yaml
groups:
  - name: llm-gateway-symptoms
    rules:
      - alert: LLMGatewayHighErrorRatio
        expr: |
          sum by (requested_model) (rate(litellm_proxy_failed_requests_metric_total[5m]))
            / sum by (requested_model) (rate(litellm_proxy_total_requests_metric_total[5m])) > 0.05
        for: 10m
        labels: { severity: page }
        annotations:
          summary: "LLM error ratio above 5% for {{ $labels.requested_model }}"
          runbook_url: "https://llm.example.com/runbooks/llm-errors"
```

## How it plugs into the stack

Recommended alert set (thresholds are starting points; set them from your SLOs and observed baselines):

| Alert               | Expression idea                                                                                     | Severity                                                   |
| ------------------- | --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Engine/gateway down | `up{job=~"vllm\|sglang\|llamacpp\|litellm"} == 0` for 2–5m                                          | page                                                       |
| Gateway error ratio | failed / total LiteLLM requests per model > 5% for 10m                                              | page                                                       |
| Gateway p95 latency | `histogram_quantile(0.95, …litellm_request_total_latency_metric_bucket…)` > target                  | page                                                       |
| Engine p95 TTFT     | `histogram_quantile(0.95, …vllm:time_to_first_token_seconds_bucket…)` > target                      | page (if TTFT is an SLO)                                   |
| Deployment outage   | `litellm_deployment_state == 2`                                                                     | page if it's the only deployment for a model, else warning |
| Queueing            | `vllm:num_requests_waiting > 0` sustained, or `sglang:num_queue_reqs`, `llamacpp:requests_deferred` | warning                                                    |
| KV-cache pressure   | `vllm:kv_cache_usage_perc > 0.95` sustained, or `rate(vllm:num_preemptions_total[5m]) > 0`          | warning                                                    |
| Truncation          | share of `vllm:request_success_total{finished_reason="length"}` rising                              | warning                                                    |
| GPU XID             | `DCGM_FI_DEV_XID_ERRORS > 0`                                                                        | warning (page if it correlates with errors)                |
| GPU temperature     | `DCGM_FI_DEV_GPU_TEMP` above vendor guidance for 10m                                                | warning                                                    |
| Spend spike         | `sum(rate(litellm_spend_metric_total[1h]))` > N × its 7-day average                                 | warning                                                    |
| Pricing gap         | `increase(litellm_zero_cost_requests_total[1h]) > 0`                                                | warning                                                    |
| Logging broken      | `increase(litellm_callback_logging_failures_metric_total[15m]) > 0`                                 | warning (page if audit logging is mandatory)               |

## Operating

- Every alert needs an owner and a runbook URL in `annotations`. If nobody would act on it at 3 a.m., it is not a page.
- Use `for:` to absorb blips (model swaps in llama-swap, rolling restarts); use `keep_firing_for:` to stop flapping on recovery.
- Silence during planned maintenance (Alertmanager silences) instead of editing rules.
- Test each alert once: stop a backend, block a port, or run a load test that forces queueing, and confirm the notification arrives.
- Review alert volume monthly; delete or demote alerts that never led to action.

## Tuning knobs worth knowing

- `evaluation_interval` (global) and per-group `interval`.
- `for` / `keep_firing_for` per rule.
- `labels.severity` drives Alertmanager routing; keep a small fixed set (`page`, `warning`).
- Recording rules (see `prometheus-grafana.md`) make alert expressions cheaper and easier to read.

## Known pitfalls

- **Division by zero at low traffic**: error-ratio alerts on idle models flap or go NaN. Add a minimum-traffic guard, e.g. `and sum by (requested_model) (rate(litellm_proxy_total_requests_metric_total[5m])) > 0.1`.
- **Alerting on GPU memory used**: engines pre-allocate it; use KV-cache usage instead.
- **Alerting on causes as pages** (GPU util, temperature) wakes people for things users don't feel.
- **Metric name drift** after upgrades silently breaks rules (the expression just returns nothing). Add an `absent()` alert for one key metric per job, or alert on `up`.
- **Unknown label names** in templates: `{{ $labels.x }}` renders empty if the label isn't on the series after aggregation; keep labels in `by (...)`.
- **llama-swap model unloading** makes per-model backends disappear by design; don't page on their absence.

## Official links

- Prometheus alerting rules: https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/
- Alertmanager: https://prometheus.io/docs/alerting/latest/alertmanager/
- Alerting practices: https://prometheus.io/docs/practices/alerting/
- Google SRE book, monitoring distributed systems (symptoms vs causes): https://sre.google/sre-book/monitoring-distributed-systems/
