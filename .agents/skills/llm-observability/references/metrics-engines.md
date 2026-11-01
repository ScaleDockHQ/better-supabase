# Engine metrics: vLLM, SGLang, llama.cpp, TGI, llama-swap

> Verified against vLLM v0.31.0, SGLang v0.5.21, llama.cpp v0.6.0 and master b11556 (server source; default port 9931 since b11521), TGI v3.3.7, llama-swap v263 (internal/server/server.go, api.go, auth.go), 2026-10-11

## What it is and when to choose it

Every common OpenAI-compatible engine exposes Prometheus metrics on its HTTP port. These are the cheapest, safest signal: no prompt content, low overhead, and they answer "is it fast, is it queueing, is it full". Scrape them directly from each engine; scrape the gateway separately (see `gateway-logging.md`) for the user-facing view.

| Engine                   | Enable                                         | Default port                             | Path       | Auth on `/metrics`                       | Prefix       |
| ------------------------ | ---------------------------------------------- | ---------------------------------------- | ---------- | ---------------------------------------- | ------------ |
| vLLM                     | always on                                      | 8000                                     | `/metrics` | **none**, even with `--api-key`          | `vllm:`      |
| SGLang                   | `--enable-metrics`                             | 30000                                    | `/metrics` | **none**, always exempt from `--api-key` | `sglang:`    |
| llama.cpp `llama-server` | `--metrics` (env `LLAMA_ARG_ENDPOINT_METRICS`) | 9931 (8080 before b11521, incl. v0.6.0)  | `/metrics` | required when `--api-key` is set         | `llamacpp:`  |
| TGI                      | always on                                      | container port 80 (often mapped to 8080) | `/metrics` | n/a                                      | `tgi_`       |
| llama-swap               | always on                                      | 8080 (`-listen`)                         | `/metrics` | see pitfalls                             | `llamaswap_` |

vLLM's auth middleware guards only the `/v1`, `/v2`, `/inference` and `/cohere` route prefixes; SGLang exempts paths starting with `/health`, `/ready` and `/metrics`; llama.cpp's only public paths are `/health`, `/v1/health` and the web UI. Treat unauthenticated `/metrics` as a network-exposure question: bind or firewall it to the Prometheus host.

## Install

Nothing extra. Enable metrics with the flag in the table and confirm:

```bash
curl -fsS http://node-a:8000/metrics  | grep -c '^vllm:'
curl -fsS http://node-a:30000/metrics | grep -c '^sglang:'
curl -fsS -H "Authorization: Bearer $LLAMA_API_KEY" http://node-a:9931/metrics | grep -c '^llamacpp:'
```

## Minimal working config

```bash
vllm serve <model> --port 8000                                  # metrics on :8000/metrics
python -m sglang.launch_server --model-path <model> --enable-metrics --port 30000
llama-server -m <model.gguf> --port 9931 --metrics
```

Prometheus side: see `assets/prometheus.yml`.

## How it plugs into the stack

### vLLM

Labels: `model_name` (served model name) and `engine` (engine index). Counters are exposed with a `_total` suffix.

| Question          | Metric                                                                                                                                                                                                                              |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Load              | `vllm:num_requests_running`, `vllm:num_requests_waiting`                                                                                                                                                                            |
| KV-cache pressure | `vllm:kv_cache_usage_perc` (0–1), `vllm:num_preemptions_total`                                                                                                                                                                      |
| Throughput        | `rate(vllm:prompt_tokens_total[5m])`, `rate(vllm:generation_tokens_total[5m])`                                                                                                                                                      |
| Outcomes          | `vllm:request_success_total{finished_reason=...}` (`stop`, `length`, `abort`, …)                                                                                                                                                    |
| Latency split     | `vllm:request_queue_time_seconds`, `vllm:time_to_first_token_seconds`, `vllm:inter_token_latency_seconds`, `vllm:request_prefill_time_seconds`, `vllm:request_decode_time_seconds`, `vllm:e2e_request_latency_seconds` (histograms) |
| Prefix caching    | `vllm:prefix_cache_hits_total` / `vllm:prefix_cache_queries_total`                                                                                                                                                                  |

Useful queries:

```promql
# p95 TTFT per model
histogram_quantile(0.95, sum by (model_name, le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))
# generation tokens/s per instance
sum by (instance, model_name) (rate(vllm:generation_tokens_total[5m]))
# prefix cache hit ratio
sum(rate(vllm:prefix_cache_hits_total[5m])) / sum(rate(vllm:prefix_cache_queries_total[5m]))
# share of requests truncated by max_tokens
sum(rate(vllm:request_success_total{finished_reason="length"}[15m])) / sum(rate(vllm:request_success_total[15m]))
```

Official dashboards: `examples/observability/prometheus_grafana/grafana.json`, and `examples/observability/dashboards/grafana/performance_statistics.json` / `query_statistics.json` in the vLLM repo.

### SGLang

Label: `model_name`. Key metrics:

| Question              | Metric                                                                                                                                                     |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Load                  | `sglang:num_running_reqs`, `sglang:num_queue_reqs`                                                                                                         |
| KV pool usage         | `sglang:token_usage`, `sglang:num_used_tokens`                                                                                                             |
| Throughput            | `sglang:gen_throughput`, `rate(sglang:prompt_tokens_total[5m])`, `rate(sglang:generation_tokens_total[5m])`                                                |
| Latency               | `sglang:time_to_first_token_seconds`, `sglang:inter_token_latency_seconds`, `sglang:e2e_request_latency_seconds`, `sglang:queue_time_seconds` (histograms) |
| Outcomes              | `sglang:num_requests_total`, `sglang:num_aborted_requests_total`                                                                                           |
| Caching / spec decode | `sglang:cache_hit_rate`, `sglang:spec_accept_rate`, `sglang:spec_accept_length`                                                                            |

Official dashboard: `examples/monitoring/grafana/dashboards/json/sglang-dashboard.json` (with a compose setup in `examples/monitoring/`).

### llama.cpp server

No model label: one series set per process (add a `model` label in the scrape config). In router mode (multiple models in one server) `/metrics` needs `?model=<id>`; scrape once per model with `params`.

| Metric                                                                                          | Type            | Meaning                                     |
| ----------------------------------------------------------------------------------------------- | --------------- | ------------------------------------------- |
| `llamacpp:prompt_tokens_total`, `llamacpp:tokens_predicted_total`                               | counter         | Prompt and generated tokens                 |
| `llamacpp:prompt_seconds_total`, `llamacpp:tokens_predicted_seconds_total`                      | counter         | Time spent in prefill / generation          |
| `llamacpp:prompt_tokens_seconds`, `llamacpp:predicted_tokens_seconds`                           | gauge           | Average prefill / generation throughput     |
| `llamacpp:requests_processing`, `llamacpp:requests_deferred`                                    | gauge           | Busy slots and queued requests              |
| `llamacpp:n_tokens_max`                                                                         | counter         | High watermark of the context size observed |
| `llamacpp:n_decode_total`, `llamacpp:n_busy_slots_per_decode`                                   | counter / gauge | Decode calls, average batch occupancy       |
| `llamacpp:spec_decode_num_draft_tokens_total`, `llamacpp:spec_decode_num_accepted_tokens_total` | counter         | Speculative decoding acceptance             |

`GET /slots` (on by default; `--no-slots` disables) gives per-slot state including sampling params; it is for debugging, not scraping, and can reveal request details.

### TGI

`tgi_request_count`, `tgi_request_success`, `tgi_request_duration`, `tgi_request_queue_duration`, `tgi_request_inference_duration`, `tgi_request_mean_time_per_token_duration`, `tgi_request_input_length`, `tgi_request_generated_tokens`, `tgi_queue_size`, `tgi_batch_current_size`, `tgi_batch_current_max_tokens`. TGI is in maintenance mode upstream; prefer vLLM or SGLang for new deployments.

### llama-swap

`/metrics` exposes host and GPU metrics, not per-request token metrics: `llamaswap_gpu_util_percent`, `llamaswap_gpu_memory_used_bytes`, `llamaswap_gpu_memory_total_bytes`, `llamaswap_gpu_memory_util_percent`, `llamaswap_gpu_power_draw_watts`, `llamaswap_gpu_temperature_celsius`, `llamaswap_gpu_fan_speed_percent` (labels `id`, `name`, sometimes `uuid`), plus `llamaswap_cpu_util_percent`, `llamaswap_memory_used_bytes`, `llamaswap_memory_total_bytes`, `llamaswap_swap_used_bytes`, `llamaswap_load_average`, `llamaswap_network_bytes_total`.

Other endpoints: `/running` (loaded models), `/logs`, `/logs/stream` (and `/logs/stream/{proxy,upstream,http,<model_id>}`), `/health`, and `/upstream/<model_id>/...` which passes requests straight to that model's backend server. Scraping backends through `/upstream/<model_id>/metrics` is possible in principle, but in llama-swap v263 a request to a model that is not loaded makes llama-swap load it (and swap others out), unless the path matches `upstream.ignorePaths` (then it returns 409). Prefer scraping the backend port directly, add `^/metrics$` to `upstream.ignorePaths` (keep the default entries), or only scrape models you keep loaded. Grafana example: `docs/grafana/example-dashboard.json` in the llama-swap repo.

## Operating

- Scrape every 15–30 s; 5 s only for short debugging sessions.
- After any engine upgrade, re-run `curl .../metrics | cut -d'{' -f1 | sort -u` and diff against the dashboard queries.
- vLLM: `--show-hidden-metrics-for-version=<prev minor>` temporarily re-enables metrics deprecated in the current version while you migrate dashboards.
- Keep per-engine dashboards; build the cross-engine overview at the gateway.

## Tuning knobs worth knowing

- vLLM `--otlp-traces-endpoint <url>` and `--collect-detailed-traces <modules>` export OpenTelemetry request traces (see `tracing.md`); detailed traces add overhead.
- vLLM `--enable-mfu-metrics` adds model FLOPs-utilization style metrics.
- llama.cpp `--slots` / `--no-slots` controls the `/slots` endpoint.
- llama-swap `metricsMaxInMemory` (default 1000) and `store.path` (sqlite) control its activity history; `captureBuffer` (MB, default 10, `0` disables) stores request/response captures, which is a privacy decision (see `privacy.md`).

## Known pitfalls

- **Metric names drift between versions**; counters gain `_total` in exposition even when the docs list the base name. Always check the live endpoint.
- **Unauthenticated `/metrics`** on vLLM and SGLang reveals served model names and traffic. Don't expose engine ports publicly; front them with the gateway.
- **llama.cpp with `--api-key`** returns 401 on `/metrics` unless Prometheus sends the key (`Authorization: Bearer` or `X-Api-Key`).
- **Histograms per model across instances**: aggregate with `sum by (le, model_name)` before `histogram_quantile`, never average quantiles.
- **llama-swap `/metrics`** is system-level; for request latency use the backend metrics or the gateway. When llama-swap `apiKeys` are set (v263), `/metrics`, `/logs`, `/running` and `/upstream/...` require a key (`Authorization: Bearer`, Basic password or `x-api-key`); only `/health` stays open. Give Prometheus the key.
- **TTFT on reasoning models** measures first token, which may be hidden reasoning; user-perceived latency may be later.

## Official links

- vLLM metrics design: https://docs.vllm.ai/en/latest/design/metrics.html
- vLLM production metrics: https://docs.vllm.ai/en/latest/usage/metrics.html
- vLLM Prometheus/Grafana example: https://github.com/vllm-project/vllm/tree/main/examples/observability/prometheus_grafana
- SGLang production metrics: https://docs.sglang.io/references/production_metrics.html
- llama.cpp server README (`/metrics`): https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- TGI metrics: https://huggingface.co/docs/text-generation-inference/reference/metrics
- llama-swap: https://github.com/mostlygeek/llama-swap
