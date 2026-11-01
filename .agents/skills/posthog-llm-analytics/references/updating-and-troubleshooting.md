# PostHog AI Observability: updating and troubleshooting

> Verified against PostHog AI Observability docs (Troubleshooting, Self-host), posthog (Python) 7.67.0, @posthog/ai 8.13.5, 2026-10-11

## Updating

- **SDKs:** pin exact versions (`posthog==7.67.0`, `@posthog/ai`). Read the release notes on GitHub (`PostHog/posthog-python`, `PostHog/posthog-js`) before bumping, then send a canary generation. Old SDKs miss newer properties such as `$ai_stop_reason`, which the trace view uses to explain empty outputs.
- **LiteLLM:** the PostHog callback needs 1.77.3 or newer.
- **Self-hosted PostHog:** there are no tagged releases; deployments track `master`. Upgrade with `bin/upgrade-hobby` after reading the script, back up volumes first, and expect to read the runbook (`/docs/runbook/upgrading-posthog`). Kubernetes deployments for new installs are no longer supported.
- **Cloud:** nothing to update; watch the AI Observability changelog page.

```bash
pip index versions posthog 2>/dev/null | head -1 || curl -fsS https://pypi.org/pypi/posthog/json | jq -r .info.version
```

## Troubleshooting

| Symptom                           | Likely cause                                                             | Fix                                                                                                               |
| --------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| No events at all                  | Ingestion delay, wrong host or token, process exited before flush        | Check status.posthog.com; match host to region; call `posthog.shutdown()` before exit (serverless especially)     |
| Traces missing over OTLP          | Generic OTLP variables used, gRPC exporter, wrong header                 | Use `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and `..._TRACES_HEADERS`; switch to HTTP; `Authorization=Bearer <token>` |
| OTLP export rejected as too large | Body over 4 MB                                                           | `batch` processor with small `send_batch_max_size`; avoid base64 images in messages                               |
| Generation shows "No output"      | Token limit hit, provider filter, reasoning used the budget, SDK too old | Raise `max_tokens`, lower reasoning effort, update the SDK                                                        |
| No `$ai_input` or content         | Privacy mode on, content stripped, or older than 30 days                 | Check `privacy_mode`, Collector deletes; read `ai_events`, not `events`                                           |
| Cost is empty or zero             | Model not in pricing data (typical for local models)                     | Set `$ai_input_token_price` and `$ai_output_token_price` per token                                                |
| Each request is its own trace     | No shared trace id                                                       | Pass `posthog_trace_id`, or LiteLLM metadata `$ai_trace_id`                                                       |
| Sessions tab empty                | No `$ai_session_id`                                                      | Pass it per call, or set `gen_ai.conversation.id`                                                                 |
| LiteLLM sends nothing             | Version below 1.77.3, callback not listed, env names wrong               | Upgrade; `success_callback: ["posthog"]`; `POSTHOG_API_KEY` and `POSTHOG_API_URL` set                             |
| Latency looks wrong               | Wrapper measures client-side including network                           | Compare with engine metrics from `prometheus-grafana-llm`                                                         |

## Teardown

Remove the wrapper or callback, unset `POSTHOG_*` variables, delete the project token if it was created for this, and for self-hosted instances stop the stack and delete the volumes only after exporting what you need.
