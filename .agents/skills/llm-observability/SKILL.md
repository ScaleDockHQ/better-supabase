---
name: llm-observability
description: Metrics, tracing, logging, cost tracking and alerting for LLM serving and LLM apps. Use when instrumenting or debugging vLLM, SGLang, llama.cpp server, TGI or llama-swap /metrics endpoints; scraping them with Prometheus and building Grafana dashboards (TTFT, inter-token latency, tokens/s, queue depth, KV-cache usage, errors); collecting NVIDIA GPU metrics with DCGM exporter or nvidia-smi (including unified-memory systems like DGX Spark/GB10); adding request tracing with OpenTelemetry GenAI semantic conventions, Langfuse, Arize Phoenix or OpenLLMetry; configuring LiteLLM gateway callbacks, Prometheus metrics, spend logs and per-key/team cost; writing Prometheus alert rules; or reviewing prompt/PII logging, redaction and retention. Also use when latency spikes, requests queue, GPUs look idle or full, costs jump, or a dashboard shows no data.
license: MIT
metadata:
  author: ScaleDockHQ
  version: "1.2.1"
compatibility: Assumes OpenAI-compatible serving (engines directly or behind LiteLLM / llama-swap) and Prometheus-format metrics. Uses curl and jq for discovery; Prometheus, Grafana, DCGM exporter, Langfuse or Phoenix are optional components the workflows install or connect to.
---

# LLM Observability

See what LLM serving and LLM apps are doing: latency users feel, throughput, queueing, GPU state, errors, cost, and individual request traces, without leaking prompts.

**Scope.** In: engine and gateway metrics, GPU metrics, Prometheus/Grafana, OpenTelemetry tracing, Langfuse/Phoenix/OpenLLMetry, LiteLLM logging and spend, alert rules, privacy review of logs and traces. Out: deploying engines (`self-hosted-llms`, `local-llms`), gateway routing and keys (`llm-gateway`), quality evals (`llm-evals`), DGX-specific dashboards (`self-hosted-llms` sparkDash reference).

Load the reference a step names; take metric names, flags and config keys from references or upstream docs, not memory.

## Discover first

Read-only. Replace hosts/ports with what exists; never print keys (presence checks only).

```bash
# What's already deployed?
ls prometheus.yml prometheus/ grafana/ docker-compose*.y*ml compose*.y*ml 2>/dev/null
grep -rIl -E 'job_name|scrape_configs' . 2>/dev/null | head
grep -rIl -E 'langfuse|phoenix|otel|OTEL_EXPORTER|traceloop|success_callback|callbacks:' --include='*.y*ml' --include='*.env*' . 2>/dev/null | head
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null | grep -iE 'vllm|sglang|llama|litellm|tgi|text-generation|prometheus|grafana|dcgm|langfuse|phoenix|otel'
command -v prometheus promtool grafana-server nvidia-smi dcgm-exporter docker 2>/dev/null

# Prometheus / Grafana already running?
curl -fsS http://localhost:9090/-/ready; curl -fsS http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)\t\(.scrapeUrl)"'
curl -fsS http://localhost:3000/api/health | jq .

# Which models does the endpoint serve?
curl -fsS -H "Authorization: Bearer ${LLM_API_KEY:-none}" "${LLM_BASE_URL:-http://localhost:4000/v1}/models" | jq -r '.data[].id'

# Engine and gateway /metrics (only first lines; look at metric prefixes)
curl -fsS http://localhost:8000/metrics | grep -E '^vllm:' | cut -d'{' -f1 | sort -u | head -40          # vLLM
curl -fsS http://localhost:30000/metrics | grep -E '^sglang:' | cut -d'{' -f1 | sort -u | head -40      # SGLang (--enable-metrics)
curl -fsS http://localhost:9931/metrics | grep -E '^llamacpp:' | cut -d' ' -f1 | sort -u                # llama.cpp (--metrics; 8080 on older builds)
curl -fsS http://localhost:8080/metrics | grep -E '^llamaswap_' | cut -d'{' -f1 | sort -u               # llama-swap
curl -fsS -H "Authorization: Bearer ${LITELLM_API_KEY:-none}" http://localhost:4000/metrics | grep -E '^litellm_' | cut -d'{' -f1 | sort -u | head -40
curl -fsS http://localhost:9400/metrics | grep -E '^DCGM_FI_' | cut -d'{' -f1 | sort -u                  # DCGM exporter
nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu,power.draw --format=csv 2>/dev/null

# Tracing backends
curl -fsS http://localhost:3000/api/public/health 2>/dev/null | jq .     # Langfuse
curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:6006/        # Phoenix
```

Ask only what discovery cannot answer:

1. Who consumes this (on-call humans, cost owners, app developers)?
2. Which SLOs matter (TTFT, end-to-end latency, error rate) and at what targets?
3. May prompts and outputs be stored at all? Where, for how long, who can read them?
4. Where do alerts go (Alertmanager receiver, chat, pager)?

## Decision flow

```
What do you need?
├─ "Is it healthy / fast enough?"        → gateway + engine metrics → Prometheus → Grafana   (metrics-engines, prometheus-grafana)
├─ "Why is it slow?"                     → queue time vs TTFT vs ITL, KV cache, preemptions  (metrics-engines)
│    └─ GPU saturated or idle?           → DCGM exporter / nvidia-smi                       (gpu-metrics)
├─ "What happened in this request/chain?"→ OpenTelemetry traces → Langfuse or Phoenix       (tracing)
├─ "Who is spending what?"               → LiteLLM spend logs + litellm_spend_metric        (gateway-logging, cost-tracking)
├─ "Tell me when it breaks"              → symptom alerts on SLOs, cause alerts as warnings (alerting)
└─ "Are we logging prompts / PII?"       → privacy review before turning anything on        (privacy)
```

Order of work: **metrics → traces → logs**. Metrics are cheap and safe; traces and logs carry content and cost.

## Rules

- **Measure the user-facing path.** TTFT, end-to-end latency, tokens/s, queue time and errors at the gateway first; engine internals second.
- **Metrics before traces before logs.** Add the cheapest, least sensitive signal first; add the next only for a question it answers.
- **Prompts are sensitive data.** Prompt and completion content is off by default in traces, logs and spend logs until someone decides otherwise, in writing.
- **Alert on symptoms, not causes.** Page on SLO breaches (latency, errors, availability); keep GPU temperature or KV-cache pressure as warnings or dashboards.
- **Label by model and backend.** Every series should say which model and which backend/deployment it came from; avoid per-user or per-request labels.
- **Retention is a decision.** Set retention for metrics, traces, logs and spend logs explicitly; the default is often "forever".
- **Protect metrics endpoints.** `/metrics` leaks model names, traffic and sometimes key aliases or emails; keep it on private networks or behind auth.
- **Verify against the live endpoint.** Metric names change between engine versions; curl `/metrics` before writing a query.

## Workflows

### 1. Inventory what's exposed

- [ ] Run the discovery block; list every engine, gateway and GPU host with its metrics URL and auth.
- [ ] Note engine versions (metric names differ by version) and whether metrics are enabled (SGLang `--enable-metrics`, llama.cpp `--metrics`, LiteLLM `callbacks: ["prometheus"]`).
- [ ] Record which endpoints are unauthenticated and reachable from where. → `references/metrics-engines.md`

### 2. Scrape engine and gateway metrics

- [ ] Start from `assets/prometheus.yml`; one job per component type, a `model` / `backend` label per target.
- [ ] Add auth for LiteLLM `/metrics` (bearer key via `credentials_file`) or use its dedicated metrics port on a private network.
- [ ] llama.cpp in router mode needs `?model=` on `/metrics`.
- [ ] `promtool check config prometheus.yml`, reload, confirm targets are `up`. → `references/prometheus-grafana.md`

### 3. GPU metrics

- [ ] Run DCGM exporter (port 9400) on each NVIDIA host; add the scrape job.
- [ ] On unified-memory systems (DGX Spark / GB10) do not trust framebuffer memory fields; use host memory metrics instead.
- [ ] Join GPU and engine panels by host label. → `references/gpu-metrics.md`

### 4. Dashboards

- [ ] Import the official vLLM Grafana dashboard (and SGLang / llama-swap / DCGM ones as relevant).
- [ ] Add a gateway overview: request rate, error rate, p50/p95 latency and TTFT per model, spend.
- [ ] Use recording rules for expensive histogram quantiles. → `references/prometheus-grafana.md`

### 5. Request tracing

- [ ] Decide the backend: Langfuse (LLM-centric UI, costs, prompts; deep dive in the `langfuse` skill) or Phoenix (OTel-native, evals) or any OTLP backend.
- [ ] Instrument the app (OpenLLMetry or OTel GenAI instrumentation) and/or the gateway (LiteLLM `otel` / `langfuse_otel` callback; the latter needs `LITELLM_OTEL_V2=true`).
- [ ] Turn content capture **off** first; enable per environment only after the privacy review.
- [ ] Propagate `traceparent` from app to gateway. → `references/tracing.md`

### 6. Gateway logging and spend

- [ ] Enable LiteLLM Prometheus callback; restrict high-cardinality and PII labels with `prometheus_metrics_config`.
- [ ] Add logging callbacks (Langfuse / OTel) with `turn_off_message_logging: true` unless content logging is approved.
- [ ] Keep `store_prompts_in_spend_logs` off; set `maximum_spend_logs_retention_period`. → `references/gateway-logging.md`

### 7. Cost tracking

- [ ] Set `input_cost_per_token` / `output_cost_per_token` (or explicit `0`) for every self-hosted model so spend is not silently zero.
- [ ] Track spend by team/key/model from `litellm_spend_metric` and `/spend/logs`; watch `litellm_zero_cost_requests_total`.
- [ ] For self-hosted capacity, derive cost per 1M tokens from hardware cost and measured throughput. → `references/cost-tracking.md`

### 8. Alerting

- [ ] Start from `assets/alert-rules.yml`; set thresholds from your SLOs, not from the template.
- [ ] Page on symptoms (availability, error ratio, latency/TTFT SLO); warn on causes (queueing, KV cache, GPU temperature, XID errors).
- [ ] `promtool check rules alert-rules.yml`; test each alert by forcing it once. → `references/alerting.md`

### 9. Privacy review

- [ ] List every place content can land: engine logs, gateway logs, spend logs, traces, llama-swap captures, eval artifacts.
- [ ] Decide per place: off, redacted, or on with retention and access control. Write it down.
- [ ] Remove PII labels (emails, client IPs, user agents) from metrics. → `references/privacy.md`

### 10. Troubleshoot

- [ ] No data → target down, wrong port/path, metrics not enabled, auth failing (`/api/v1/targets` `lastError`).
- [ ] High latency → split into queue time, prefill (TTFT) and decode (ITL); check running vs waiting requests and KV-cache usage.
- [ ] GPU idle but slow → client concurrency, gateway limits, CPU-bound tokenization, or a different backend serving the model.
- [ ] Spend is zero → missing pricing for the model. → `references/metrics-engines.md`, `references/cost-tracking.md`

## Reference index

| Reference                          | Load when                                                                |
| ---------------------------------- | ------------------------------------------------------------------------ |
| `references/metrics-engines.md`    | Enabling and reading vLLM, SGLang, llama.cpp, TGI and llama-swap metrics |
| `references/gpu-metrics.md`        | Stack notes: DCGM exporter, nvidia-smi, unified-memory caveats           |
| `references/prometheus-grafana.md` | Stack notes: scrape targets, ports, auth, dashboards                     |
| `references/tracing.md`            | Stack notes: where spans come from, propagation, content capture         |
| `references/gateway-logging.md`    | LiteLLM callbacks, Prometheus metrics, spend logs, OSS vs Enterprise     |
| `references/cost-tracking.md`      | Pricing config, spend by key/team/model, self-hosted cost per token      |
| `references/alerting.md`           | Alert rule design and examples                                           |
| `references/privacy.md`            | Prompt/PII logging, redaction, retention, access                         |

Templates: `assets/prometheus.yml` (vLLM, SGLang, llama.cpp, llama-swap, LiteLLM, DCGM targets with placeholders), `assets/alert-rules.yml` (symptom and cause alerts).

## Companion skills

Install any of them with `npx skills add ScaleDockHQ/llm-skills --skill <name>`.

- `self-hosted-llms` — engines and llama-swap being monitored; its sparkDash reference covers DGX-specific monitoring.
- Tracing and metrics depth: `opentelemetry-genai`, `openllmetry`, `arize-phoenix`, `mlflow-tracing`, `weave`, `posthog-llm-analytics`, `datadog-llm-observability`, `sentry-ai-monitoring`, `prometheus-grafana-llm`, `dcgm-exporter`, `sparkdash`.
- `langfuse` — installing, operating and upgrading Langfuse, its SDK and OTLP ingestion, retention and masking.
- `llm-gateway` — LiteLLM setup, keys, teams and budgets behind the spend metrics.
- `llm-evals` — quality signals; production failures become golden-set items.
- `local-llms`, `cloud-llms`, `choosing-llm-hosting` — where the traffic runs.
- `llm-clients` — client-side instrumentation and `traceparent` propagation.
