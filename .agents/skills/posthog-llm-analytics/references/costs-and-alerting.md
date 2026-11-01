# PostHog AI Observability: costs, analysis and alerting

> Verified against PostHog AI Observability docs (Calculating LLM costs, Alerts, Dashboard), 2026-10-11

## Cost on self-hosted models

PostHog prices a generation from `$ai_provider` and `$ai_model` using OpenRouter's pricing data, falling back to its own table. A locally served model usually has no match, so cost is empty. Set custom prices as properties on the call:

- `$ai_input_token_price` and `$ai_output_token_price` (required together), plus optional `$ai_cache_read_token_price`, `$ai_cache_write_token_price`, `$ai_request_price`, `$ai_web_search_price`.
- Prices are per single token, not per million: `0.03 / 1_000_000 = 0.00000003`.
- Use `0` for sunk-cost hardware, or an amortized figure (GPU cost per hour divided by tokens per hour) if you want comparable cost views.
- Cache accounting: Anthropic-style counts cache tokens separately, everything else includes them in input tokens. Override with `$ai_cache_reporting_exclusive`.

## Where to look

The AI Observability dashboard shows users, traces, costs, generations and latency, and is editable like any dashboard. Traces, generations, spans, sessions, clusters and evaluations are tabs in the app. The same data is available by SQL (`ai_events` for content, `events` for metadata) and through PostHog's MCP server and API.

## Alerting

Alerts attach to saved insights, not to LLM events directly. Supported insight types are trends, funnels (steps and trends views) and SQL (HogQL). Build an insight, then Monitor, Alerts, New alert.

Useful insights:

- Trend of `$ai_generation` where `$ai_is_error` is true, divided by all generations (formula) with a threshold alert.
- Trend of the average of `$ai_latency`, or `$ai_time_to_first_token`, with an upper bound.
- Sum of `$ai_total_cost_usd` per day with an upper bound.
- A "has value, less than 1" alert on `$ai_generation` to catch a pipeline that stopped sending.

Check frequency options and limits (a free tier cap on alert count, plan-gated real-time and 15-minute checks) are in the Alerts docs and may change; read them at use time. Engine-level alerting (queue depth, KV cache, GPU) belongs in Prometheus: see `prometheus-grafana-llm` and `dcgm-exporter`.

## Evaluations

AI Observability has evaluations (LLM-as-judge and code-based) that run on generations. Method guidance is in `llm-evals`; the PostHog configuration lives in the Evaluations docs page, not verified in depth here.
