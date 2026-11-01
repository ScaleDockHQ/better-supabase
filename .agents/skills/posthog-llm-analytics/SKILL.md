---
name: posthog-llm-analytics
description: "PostHog AI Observability (formerly LLM analytics): traces, cost, latency and evaluations built on $ai_generation events. Use to send traces from vLLM, llama.cpp, SGLang, Ollama or LiteLLM into PostHog, wrap OpenAI clients, export OTLP, set privacy_mode, price local models, alert on insights, self-host or update PostHog, or fix missing traces and empty cost. Not for choosing a stack (llm-observability)."
license: MIT
compatibility: Python 3.9+ or Node 18+ with pip or npm, bash, curl and jq; optional Docker for an OpenTelemetry Collector. Needs a PostHog project token (Cloud or self-hosted). Sending prompts to a hosted service and installs need the user's explicit approval.
metadata:
  author: ScaleDockHQ
  version: "0.1.0"
---

# PostHog AI Observability

A working PostHog AI Observability setup that records every LLM call from self-hosted endpoints and gateways as traces with user, cost and latency, keeps prompt content under an explicit privacy decision, and alerts through PostHog insights.

**Scope:** this one product: SDK wrappers, LiteLLM callback, OTLP, privacy mode, retention, cost for local models, alerts, hosting, update, troubleshoot. Choosing between PostHog, Langfuse, Weave and others is `llm-observability`; engine metrics (`vllm:*`, `sglang:*`, `llamacpp:*`) are `prometheus-grafana-llm`; the LiteLLM proxy itself is `litellm`; eval methodology is `llm-evals`.

Work through the steps in order. Load a reference only when a step names it.

## Discover first

Read-only, never prints secret values.

```bash
pip show posthog litellm 2>/dev/null | grep -E '^(Name|Version)'
grep -rIlE --include='*.py' --include='*.ts' 'posthog' . 2>/dev/null | head
env | cut -d= -f1 | grep -E '^(POSTHOG_|OTEL_EXPORTER)' || true      # names only
docker ps --format '{{.Names}}\t{{.Image}}' | grep -Ei 'posthog|otel|litellm' || true
curl -fsS https://pypi.org/pypi/posthog/json | jq -r .info.version     # newest Python SDK
```

Ask only what discovery cannot show: PostHog Cloud (US or EU) or self-hosted; which clients or gateway send calls (Python, Node, other, LiteLLM); whether prompts may leave the network.

## Decision flow

1. **Prompts may not leave your network:** self-hosted PostHog, or privacy mode so only metadata is sent. -> `references/privacy-and-retention.md`
2. **Python or Node app calling an OpenAI-compatible local server:** wrapped OpenAI client. -> `references/setup-and-sdks.md`
3. **LiteLLM proxy in front of the engines:** the `posthog` callback. -> `references/otlp-and-gateways.md`
4. **Other language or OTel source:** OTLP over HTTP to `/i/v0/ai/otel`. -> `references/otlp-and-gateways.md`
5. **Cost is empty for a local model:** custom per-token prices. -> `references/costs-and-alerting.md`
6. **Alerts and dashboards:** -> `references/costs-and-alerting.md`
7. **SDK or self-hosted update, or an error:** -> `references/updating-and-troubleshooting.md`

## Rules

- **Ask before sending data off the machine.** PostHog Cloud is third-party hosting; get approval and decide content capture first.
- **Secrets never touch output.** The project token and any personal API key live in `0600` env files; check presence by name only.
- **Content capture is a decision.** Prompts and completions go in `$ai_input` and `$ai_output_choices`. Use `privacy_mode`, or strip at a Collector, before real traffic. PostHog does not redact PII for you.
- **Large properties expire after 30 days.** Read content from the `ai_events` table; metadata stays.
- **OTLP is HTTP only,** with `Authorization: Bearer <token>`, at `/i/v0/ai/otel`, bodies under 4 MB.
- **Alerts attach to insights,** not raw events; engine-level alerts belong in Prometheus.
- **Pin SDKs and flush.** Exact versions in lock files; call `shutdown()` before short-lived processes exit.
- **Verify upstream.** The product was renamed and docs move; read the docs and PyPI at use time.

## Workflows

### First trace

- [ ] Install the SDK (pin), set `POSTHOG_PROJECT_TOKEN` and host from a file -> `references/setup-and-sdks.md`.
- [ ] Wrap the client, make one call with a `posthog_trace_id`, call `shutdown()`.
- [ ] Open AI Observability, confirm one generation with model, tokens, latency.

### Gateway or OTel path

- [ ] LiteLLM callback (`assets/litellm-posthog.yaml`) or Collector (`assets/otel-collector.yaml`) -> `references/otlp-and-gateways.md`.
- [ ] Canary request; confirm the trace and that content matches the privacy decision.

### Privacy

- [ ] Turn on `privacy_mode` or Collector stripping; canary string must not appear -> `references/privacy-and-retention.md`.

### Cost and alerts

- [ ] Set per-token prices for local models; build error-rate, latency and cost insights; add alerts -> `references/costs-and-alerting.md`.

## Reference index

| File                                         | Read when                                                                    |
| -------------------------------------------- | ---------------------------------------------------------------------------- |
| `references/setup-and-sdks.md`               | Cloud versus self-hosted, Python and Node wrappers, manual capture, identity |
| `references/otlp-and-gateways.md`            | LiteLLM callback, OTLP endpoint, attribute mapping, engines                  |
| `references/privacy-and-retention.md`        | Privacy mode, stripping, 30-day retention, access, canary test               |
| `references/costs-and-alerting.md`           | Pricing local models, dashboard, insight alerts, evaluations                 |
| `references/updating-and-troubleshooting.md` | SDK and self-hosted updates, symptom to cause to fix, teardown               |

Templates: `assets/otel-collector.yaml` (validated), `assets/litellm-posthog.yaml`. Script: `scripts/check.sh` (names and reachability only).

## Companion skills

- `llm-observability`: choosing a stack. Install: `npx skills add ScaleDockHQ/llm-skills --skill llm-observability`.
- `litellm`: the proxy. Install: `npx skills add ScaleDockHQ/llm-skills --skill litellm`.
- `prometheus-grafana-llm`: engine metrics and alerts. Install: `npx skills add ScaleDockHQ/llm-skills --skill prometheus-grafana-llm`.
- `llm-evals`: evaluation method. Install: `npx skills add ScaleDockHQ/llm-skills --skill llm-evals`.
