# Privacy: prompts, PII, redaction and retention

> Verified against LiteLLM v1.105.0 docs, llama-swap v263 config example, Langfuse v4.56.0 docs, Arize Phoenix 20.20.0 docs, OpenLLMetry 0.62.4 docs, OpenTelemetry GenAI semantic conventions (2026-10-09), llama.cpp server README, 2026-10-11

## What it is and when to choose it

Prompts and completions routinely contain personal data, credentials pasted by users, customer documents and proprietary code. Observability tooling is built to keep data, so it is often the largest unreviewed copy of that content. Run this review **before** enabling traces or logging callbacks, and again whenever a new tool or callback is added.

Default stance: **metrics on, content off, retention set, access restricted.** Turn content on only for a specific purpose, environment and period, with a written decision.

## Install

Nothing to install. Produce an inventory with the discovery commands in `SKILL.md`, then fill in the table below.

## Minimal working config

Content-off baseline across the stack:

```yaml
# LiteLLM config.yaml
litellm_settings:
  callbacks: ["prometheus"]
  prometheus_exclude_labels: [user_email, client_ip, user_agent, end_user]
  turn_off_message_logging: true
  redact_user_api_key_info: true
callback_settings:
  otel:
    message_logging: false
general_settings:
  store_prompts_in_spend_logs: false
  maximum_spend_logs_retention_period: "30d"
```

```yaml
# llama-swap config.yaml
captureBuffer: 0 # disable request/response captures (default 10 MB in memory)
```

```bash
# App / instrumentation env
export TRACELOOP_TRACE_CONTENT=false                       # OpenLLMetry
export OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=false   # name used by OTel GenAI instrumentations that follow the spec example; check your library
export PHOENIX_DEFAULT_RETENTION_POLICY_DAYS=30            # Phoenix server
```

## How it plugs into the stack

Where content and PII can land, and the control for each:

| Place                                              | What it can contain                                                                                                                                                                         | Control                                                                                                                                                                 |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| LiteLLM logging callbacks (Langfuse, OTel, S3, …)  | Full messages and responses, key/user/team info                                                                                                                                             | `turn_off_message_logging: true`; `callback_settings.otel.message_logging: false`; `redact_user_api_key_info: true`                                                     |
| LiteLLM per-request overrides                      | Client can opt **in** with header `LiteLLM-Disable-Message-Redaction: true`, or opt **out** of all logging with `no-log: true`                                                              | Strip the override header at your ingress if clients must not enable content logging; set `global_disable_no_log_param: true` if every request must be logged for audit |
| LiteLLM spend logs (Postgres `LiteLLM_SpendLogs`)  | Metadata always; prompts/responses only if `store_prompts_in_spend_logs: true`                                                                                                              | Keep it `false`; set `maximum_spend_logs_retention_period`; restrict DB and admin UI access                                                                             |
| LiteLLM Prometheus labels                          | `user_email`, `client_ip`, `user_agent`, `end_user`, key aliases, team names                                                                                                                | `prometheus_exclude_labels` / `prometheus_metrics_config.include_labels`; protect `/metrics`                                                                            |
| llama-swap                                         | Request/response captures in memory (`captureBuffer` MB, default 10), activity history (`store.path` sqlite if set), `/logs` streams of upstream output                                     | `captureBuffer: 0`; don't set `store.path` unless needed; keep the UI, `/logs` and `/api` private                                                                       |
| Engine logs                                        | Request logging can include prompts depending on engine flags and log level                                                                                                                 | Keep request logging off or at metadata level in production; check each engine's request-logging flags before enabling them                                             |
| llama.cpp `/slots`                                 | Per-slot state for in-flight requests                                                                                                                                                       | `--no-slots` in shared deployments, or restrict access                                                                                                                  |
| OTel traces                                        | GenAI content attributes (`gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.definitions`) are Opt-In per spec, but some SDKs capture by default | Instrumentation switches (`TRACELOOP_TRACE_CONTENT=false`, library-specific flags); Collector `attributes` processor `delete` actions as a backstop (see `tracing.md`)  |
| Langfuse                                           | Everything sent to it                                                                                                                                                                       | Client-side masking, retention (Enterprise when self-hosted, otherwise kept indefinitely), access control; see the `langfuse` skill                                     |
| Phoenix                                            | Everything sent to it                                                                                                                                                                       | `PHOENIX_DEFAULT_RETENTION_POLICY_DAYS` (default 0 = keep forever); authentication and network restrictions                                                             |
| Eval artifacts (`llm-evals` outputs, CI artifacts) | Prompts and model outputs                                                                                                                                                                   | Short artifact retention; no production user data in golden sets without consent and redaction                                                                          |
| Prometheus                                         | Label values only                                                                                                                                                                           | Retention via `storage.tsdb.retention.*`; no PII labels                                                                                                                 |

**Langfuse in this stack.** It stores every prompt and completion sent to it and keeps them forever unless retention is configured, so mask at the client or keep content out until a retention plan exists.

Depth: install the langfuse skill (npx skills add ScaleDockHQ/llm-skills --skill langfuse)

## Operating

Write a one-page decision record per environment:

```markdown
## LLM observability data decision: <environment>

- Content capture: off | redacted | on (scope: <service>, reason: <...>, until: <date>)
- Where content is stored: <system>, region <...>, encrypted at rest: yes/no
- Retention: metrics <N d>, traces <N d>, spend logs <N d>, logs <N d>
- Who can read content: <group>; access reviewed <date>
- PII labels removed from metrics: yes/no (list)
- Per-request overrides: LiteLLM-Disable-Message-Redaction stripped at ingress yes/no; no-log allowed yes/no
- Legal basis / customer agreements checked: <link>
- Owner: <name>
```

Then:

- [ ] Send a canary request containing a fake marker (e.g. `PRIVACY-CANARY-<date>`) and a fake email; search every sink (Langfuse/Phoenix UI, spend logs, log aggregator, S3 bucket) for the marker. It should appear nowhere when content is off.
- [ ] Repeat the canary after every upgrade of the gateway, SDKs or engines; defaults change.
- [ ] Confirm retention jobs actually delete: the oldest row/trace date moves forward and row counts stop growing without bound.
- [ ] Review access lists quarterly.

## Tuning knobs worth knowing

- LiteLLM `x-litellm-enable-message-redaction: true` header: redact content for one request even when global logging is on.
- LiteLLM `x-litellm-disable-callbacks: <name>` header (Enterprise): skip named callbacks per request.
- Collector `attributes` processor `hash` action: keep a joinable pseudonymous ID instead of a raw user identifier.

## Known pitfalls

- **"Message logging off" ≠ "nothing sensitive logged"**: metadata (user IDs, emails in labels, IPs, custom metadata fields clients send) still flows. Review metadata too.
- **Client-controlled overrides**: `LiteLLM-Disable-Message-Redaction` lets any caller turn content logging back on for their request.
- **Infinite default retention** in Langfuse self-hosted (without EE), Phoenix (`0` days), and LiteLLM spend logs (`null`).
- **Secrets in prompts**: users paste API keys and passwords; content logging turns them into long-lived stored secrets.
- **Debug sessions left on**: temporary content capture for an investigation becomes permanent. Give every "on" decision an end date.
- **Shared dashboards** that render traces expose content to everyone with dashboard access.

## Official links

- LiteLLM logging (redaction, no-log, per-request headers): https://docs.litellm.ai/docs/proxy/logging
- LiteLLM config settings (spend logs, retention): https://docs.litellm.ai/docs/proxy/config_settings
- LiteLLM Prometheus labels: https://docs.litellm.ai/docs/proxy/prometheus
- llama-swap configuration example: https://github.com/mostlygeek/llama-swap/blob/main/config.example.yaml
- OTel GenAI conventions (sensitive attributes): https://github.com/open-telemetry/semantic-conventions-genai
- OTel handling sensitive data: https://opentelemetry.io/docs/security/handling-sensitive-data/
- Phoenix configuration: https://arize.com/docs/phoenix/self-hosting/configuration
- OpenLLMetry privacy: https://www.traceloop.com/docs/openllmetry/privacy/traces
