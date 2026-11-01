# PostHog AI Observability: OTLP, gateways and engines

> Verified against PostHog AI Observability docs (OpenTelemetry and LiteLLM installation pages), 2026-10-11

## What the engines expose

| Engine                          | Request data for PostHog                                                                                                                       | Engine metrics                                                                                          |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| vLLM, llama.cpp, SGLang, Ollama | Not emitted by PostHog itself: wrap the OpenAI-compatible client (`references/setup-and-sdks.md`), or send through a gateway that emits events | Not PostHog's job. Use the `prometheus-grafana-llm` skill for `vllm:*`, `sglang:*`, `llamacpp:*` series |
| LiteLLM proxy                   | Built-in `posthog` callback                                                                                                                    | `litellm_*` on `/metrics` (see `litellm`)                                                               |

PostHog is for per-request product and quality data (who, which prompt, cost, trace). It does not scrape Prometheus metrics, so keep both.

## LiteLLM proxy (verified)

Requires LiteLLM 1.77.3 or newer. Use `assets/litellm-posthog.yaml`: `success_callback: ["posthog"]`, optional `failure_callback`, and env `POSTHOG_API_KEY` (the project token) and `POSTHOG_API_URL`. Identity and trace travel in request `metadata`: `user_id` becomes the distinct id, and `$ai_session_id` and `$ai_trace_id` pass through. Without `$ai_trace_id` each request is its own trace.

## Direct OTLP

PostHog's endpoint is `https://us.i.posthog.com/i/v0/ai/otel` (EU: `eu.i.posthog.com`; self-hosted: your host).

- HTTP only, no gRPC. Body is `application/x-protobuf` or `application/json`.
- Auth: `Authorization: Bearer <project token>`.
- Use the traces-specific variables: `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and `OTEL_EXPORTER_OTLP_TRACES_HEADERS` (not the generic endpoint).
- Request body is capped at 4 MB. Use the `batch` processor and keep image-heavy chats small.
- GenAI semantic-convention attributes map to `$ai_*`: `gen_ai.request.model` or `gen_ai.response.model` to `$ai_model`, `gen_ai.input.messages` to `$ai_input`, `gen_ai.output.messages` to `$ai_output_choices`, `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens` to token counts, `gen_ai.operation.name=chat` to an `$ai_generation` event, `embeddings` to `$ai_embedding`, others to `$ai_span`. Trace and span ids are preserved. Unknown attributes pass through as event properties. `gen_ai.conversation.id` is used as the session id.

`assets/otel-collector.yaml` (validated with collector-contrib 0.162.0) receives on loopback 4318, deletes the message-content attributes, batches and exports with the token from the environment.

## Unverified for engines

vLLM can export OpenTelemetry spans with `--otlp-traces-endpoint`, but whether its attributes produce complete `$ai_generation` events in PostHog was not tested here. Prefer the client wrapper or LiteLLM for self-hosted models, and canary-test any direct engine export.

## Sessions and custom properties

Group multi-turn chats with `$ai_session_id` (a per-call property in the wrappers; a span attribute set in a span processor for OTel). Extra attributes such as `tenant_id` pass through and can be filtered on.
