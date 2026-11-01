# LLM Observability Skill

An agent skill for seeing what LLM serving and LLM apps are doing: latency users feel, throughput, queueing, GPU state, errors, cost and individual request traces, without leaking prompts. It covers engine metrics from vLLM, SGLang, llama.cpp, TGI and llama-swap; NVIDIA GPU metrics with DCGM exporter (including the unified-memory caveats on DGX Spark / GB10); Prometheus and Grafana; OpenTelemetry GenAI tracing with Langfuse, Arize Phoenix and OpenLLMetry; LiteLLM gateway metrics, logging and spend; alert rules; and a privacy review for prompt and PII logging.

## Install

```bash
npx skills add ScaleDockHQ/llm-skills --skill llm-observability
```

## Rules

- **Measure the user-facing path.** TTFT, end-to-end latency, tokens/s, queue time and errors at the gateway first; engine internals second.
- **Metrics before traces before logs.** Add the cheapest, least sensitive signal first.
- **Prompts are sensitive data.** Content is off by default in traces, logs and spend logs until someone decides otherwise, in writing.
- **Alert on symptoms, not causes.** Page on SLO breaches; keep GPU temperature or KV-cache pressure as warnings.
- **Label by model and backend.** Every series says which model and backend it came from; no per-user or per-request labels.
- **Retention is a decision.** Set it explicitly for metrics, traces, logs and spend logs; the default is often "forever".
- **Protect metrics endpoints.** `/metrics` leaks model names, traffic and sometimes key aliases or emails.
- **Verify against the live endpoint.** Metric names change between versions; curl `/metrics` before writing a query.

## References

The `SKILL.md` overview is always loaded; the agent pulls a reference only when a step needs it.

- [`references/metrics-engines.md`](references/metrics-engines.md): enabling and reading vLLM, SGLang, llama.cpp, TGI and llama-swap metrics, auth on `/metrics`, and the queries that matter.
- [`references/gpu-metrics.md`](references/gpu-metrics.md): DCGM exporter install and fields, nvidia-smi, and unified-memory reporting on DGX Spark / GB10.
- [`references/prometheus-grafana.md`](references/prometheus-grafana.md): scrape configs, auth with `credentials_file`, retention, recording rules and official dashboards.
- [`references/tracing.md`](references/tracing.md): OpenTelemetry GenAI conventions, Phoenix, OpenLLMetry, Collector content stripping, vLLM and LiteLLM trace export; Langfuse depth lives in the `langfuse` skill.
- [`references/gateway-logging.md`](references/gateway-logging.md): LiteLLM Prometheus metrics and labels, logging callbacks, spend logs and retention, OSS vs Enterprise.
- [`references/cost-tracking.md`](references/cost-tracking.md): pricing self-hosted models, zero-cost and budget behaviour, spend queries, cost per token for your own capacity.
- [`references/alerting.md`](references/alerting.md): symptom vs cause alerts, recommended alert set, pitfalls.
- [`references/privacy.md`](references/privacy.md): where prompts and PII land, controls per sink, canary test, decision record.

**Templates:**

- [`assets/prometheus.yml`](assets/prometheus.yml): scrape jobs for vLLM, SGLang, llama.cpp, llama-swap, LiteLLM, DCGM and node_exporter with placeholders (validated with `promtool`).
- [`assets/alert-rules.yml`](assets/alert-rules.yml): symptom (page) and cause (warning) alerts (validated with `promtool`).

## Upstream credits

- [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/): metrics storage, alerting, dashboards.
- [vLLM](https://github.com/vllm-project/vllm), [SGLang](https://github.com/sgl-project/sglang), [llama.cpp](https://github.com/ggml-org/llama.cpp), [TGI](https://github.com/huggingface/text-generation-inference), [llama-swap](https://github.com/mostlygeek/llama-swap): engine metrics and example dashboards.
- [NVIDIA DCGM exporter](https://github.com/NVIDIA/dcgm-exporter): GPU telemetry.
- [LiteLLM](https://github.com/BerriAI/litellm): gateway metrics, logging and spend tracking.
- [OpenTelemetry GenAI semantic conventions](https://github.com/open-telemetry/semantic-conventions-genai), [Langfuse](https://github.com/langfuse/langfuse), [Arize Phoenix](https://github.com/Arize-ai/phoenix), [OpenLLMetry](https://github.com/traceloop/openllmetry): tracing.

## Companion skills

From [ScaleDockHQ/llm-skills](https://github.com/ScaleDockHQ/llm-skills); install any of them with `npx skills add ScaleDockHQ/llm-skills --skill <name>`:

- `self-hosted-llms`: the engines and llama-swap being monitored; its sparkDash reference covers DGX-specific monitoring and points here for generic metrics.
- `langfuse`: installing, operating and upgrading Langfuse, its SDK and OTLP ingestion, retention and masking.
- `llm-gateway`: LiteLLM setup, keys, teams and budgets behind the spend metrics.
- `llm-evals`: quality signals; production failures become golden-set items.
- `local-llms`, `cloud-llms`, `choosing-llm-hosting`: where the traffic runs.
- `llm-clients`: client-side instrumentation and trace propagation.
- `model-quantization`, `fine-tuning-llms`, `self-hosted-genmedia`: workloads whose serving you will want to watch.

## License

MIT
