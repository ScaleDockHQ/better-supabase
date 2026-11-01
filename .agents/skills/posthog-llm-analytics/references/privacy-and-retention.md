# PostHog AI Observability: privacy, retention and access

> Verified against PostHog AI Observability docs (Privacy mode, AI event data retention), 2026-10-11

## Decide first

Prompts and completions sit in `$ai_input` and `$ai_output_choices` by default. On PostHog Cloud that is third-party storage. Decide, in writing: content on, off, or redacted; which projects; who can open them.

## Controls, strongest first

1. **Do not send content: privacy mode.** Excludes `$ai_input` and `$ai_output_choices`. Metadata (model, provider, tokens, cost, latency, ids) still arrives.
   - Client-wide: Python `Posthog(token, host=..., privacy_mode=True)`; Node `new PostHog(token, { privacyMode: true })`.
   - Per request: `posthog_privacy_mode=True` (Python wrappers) or `posthogPrivacyMode: true` (Node).
   - LangChain: `PosthogCallbackHandler(client, privacy_mode=True)`.
2. **Strip at a Collector** for OTel traffic: `assets/otel-collector.yaml` deletes `gen_ai.input.messages`, `gen_ai.output.messages` and `gen_ai.system_instructions`.
3. **LiteLLM:** `turn_off_message_logging: true` redacts content for callbacks that honor it. Canary-test the PostHog callback: send a unique string and confirm `$ai_input` is absent.
4. **Redact before sending** in your own code (scrub messages passed to the wrapper); PostHog does not do PII redaction on ingest.
5. **Self-host PostHog** if data may not leave your network (`references/setup-and-sdks.md`).

## Retention

PostHog removes the large `$ai_` properties after 30 days: `$ai_input`, `$ai_output`, `$ai_output_choices`, `$ai_input_state`, `$ai_output_state`, `$ai_tools`. Model, provider, tokens, cost, latency and ids stay under normal event retention.

- The full copy lives in the `ai_events` table; the `events` table never holds the large properties. To read content, query `posthog.ai_events` in the SQL editor.
- To keep raw content longer, set up a batch export to your own storage.

## Access and keys

- The project token is write-only for ingestion; personal API keys for reading data are secrets. Store both in `0600` files, never in prompts, logs or repos.
- Restrict who can view traces with project and organization roles.
- Send user ids as opaque ids, not emails.

## Canary test

```bash
# 1. send one call containing the string CANARY-<random> with privacy mode on
# 2. in PostHog SQL: SELECT properties.$ai_input FROM ai_events WHERE timestamp > now() - INTERVAL 1 HOUR LIMIT 5
# 3. the canary must not appear
```
