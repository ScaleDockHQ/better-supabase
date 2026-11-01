# Request tracing: OpenTelemetry GenAI, Langfuse, Phoenix, OpenLLMetry

> Verified against OpenTelemetry semantic conventions v1.44.0 and semantic-conventions-genai main (2026-10-09, status Development), Langfuse v4.56.0 docs, Arize Phoenix 20.20.0 docs, OpenLLMetry 0.62.4, vLLM v0.31.0, LiteLLM v1.105.0, OpenTelemetry Collector contrib v0.162.0, 2026-10-11

Stack notes only. Backend install, SDK setup, retention and troubleshooting live in the product skills.

## How it plugs into the stack

Where spans come from:

| Layer           | How                                                                                                                                                                                                          |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| App             | OpenLLMetry (`Traceloop.init()`), OpenInference instrumentors (Phoenix), Langfuse SDK, or OTel GenAI instrumentation                                                                                         |
| LiteLLM gateway | `litellm_settings.callbacks: ["otel"]` with `OTEL_EXPORTER`, `OTEL_ENDPOINT`, `OTEL_HEADERS`; or `["langfuse_otel"]` with `LITELLM_OTEL_V2=true` (restart the proxy). Content switches: `gateway-logging.md` |
| vLLM            | `--otlp-traces-endpoint <url>`; `OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf` for HTTP (default gRPC); `--collect-detailed-traces` costs performance                                                    |

Stack pitfalls:

- Propagate W3C `traceparent` from app to gateway and engine, and check the gateway callback continues the incoming trace.
- Decide which layer owns LLM spans; app SDK plus gateway callback double-logs.
- Langfuse does not accept OTLP gRPC; use HTTP.
- GenAI conventions are in Development; pin instrumentation versions and expect attribute churn.
- Content capture is opt-in in the spec but on by default in some SDKs and callbacks; inspect a stored span before real traffic (`privacy.md`).

Depth:

- `opentelemetry-genai`: `npx skills add ScaleDockHQ/llm-skills --skill opentelemetry-genai`
- `openllmetry`: `npx skills add ScaleDockHQ/llm-skills --skill openllmetry`
- `arize-phoenix`: `npx skills add ScaleDockHQ/llm-skills --skill arize-phoenix`
- `langfuse`: `npx skills add ScaleDockHQ/llm-skills --skill langfuse`
- `mlflow-tracing`: `npx skills add ScaleDockHQ/llm-skills --skill mlflow-tracing`
- `weave`: `npx skills add ScaleDockHQ/llm-skills --skill weave`
- `posthog-llm-analytics`: `npx skills add ScaleDockHQ/llm-skills --skill posthog-llm-analytics`
- `datadog-llm-observability`: `npx skills add ScaleDockHQ/llm-skills --skill datadog-llm-observability`
- `sentry-ai-monitoring`: `npx skills add ScaleDockHQ/llm-skills --skill sentry-ai-monitoring`
