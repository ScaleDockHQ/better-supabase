# PostHog LLM analytics

An agent skill for PostHog AI Observability (formerly LLM analytics). It covers sending traces from self-hosted endpoints and gateways (vLLM, llama.cpp, SGLang, Ollama, LiteLLM) with SDK wrappers, the LiteLLM callback and OTLP, privacy mode and retention, pricing for local models, alerts on insights, Cloud versus self-hosted PostHog, updates and troubleshooting.

## Install

```bash
npx skills add ScaleDockHQ/llm-skills --skill posthog-llm-analytics
```

## Rules

- **Ask before sending data off the machine.** PostHog Cloud is third-party hosting.
- **Secrets never touch output.** Project token in `0600` files only.
- **Content capture is a decision.** Privacy mode or Collector stripping before real traffic.
- **Large `$ai_` properties expire after 30 days.**
- **OTLP is HTTP only,** Bearer token, 4 MB cap.
- **Pin SDKs and flush before exit.**

## References

- [`references/setup-and-sdks.md`](references/setup-and-sdks.md): hosting, wrappers, manual capture.
- [`references/otlp-and-gateways.md`](references/otlp-and-gateways.md): LiteLLM, OTLP, engines.
- [`references/privacy-and-retention.md`](references/privacy-and-retention.md): privacy and retention.
- [`references/costs-and-alerting.md`](references/costs-and-alerting.md): cost, dashboard, alerts.
- [`references/updating-and-troubleshooting.md`](references/updating-and-troubleshooting.md): updates and fixes.

**Templates and scripts:** [`assets/otel-collector.yaml`](assets/otel-collector.yaml), [`assets/litellm-posthog.yaml`](assets/litellm-posthog.yaml), [`scripts/check.sh`](scripts/check.sh).

## Upstream credits

- [PostHog](https://github.com/PostHog/posthog) (MIT) and its AI Observability docs.

## Companion skills

- `llm-observability`: choosing a stack.
- `litellm`: the proxy.
- `prometheus-grafana-llm`: engine metrics.

## License

MIT
