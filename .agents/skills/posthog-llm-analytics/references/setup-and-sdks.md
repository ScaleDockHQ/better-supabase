# PostHog AI Observability: setup and SDKs

> Verified against PostHog AI Observability docs, posthog (Python) 7.67.0 and @posthog/ai 8.13.5, 2026-10-11

The product is called AI Observability in the docs (formerly LLM analytics; old URLs redirect). It is built on PostHog events: each model call is an `$ai_generation` event, grouped by `$ai_trace_id`, with `$ai_span` and `$ai_trace` events for steps.

## Choose where PostHog runs

| Option                     | Notes                                                                                                                                                                                                                                                                                                                   |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PostHog Cloud (US or EU)   | Host `https://us.i.posthog.com` or `https://eu.i.posthog.com`. Third-party hosting, so decide content capture first (`references/privacy-and-retention.md`). The docs state a monthly free allowance of `$ai_model` events; check the pricing page for current numbers.                                                 |
| Self-hosted (hobby deploy) | MIT Docker Compose on one Linux VM (docs suggest about 4 vCPU, 16 GB RAM, 30+ GB disk, an `A` record for TLS). The docs call self-hosting officially unsupported, with no tagged releases. Install and upgrade use `bin/deploy-hobby` and `bin/upgrade-hobby` from the PostHog repo. Read the script before running it. |

Use the project token from project settings as the SDK key. It is a write-only ingestion key, but still keep it in an environment variable or a `0600` file rather than in code.

## Python: wrap an OpenAI-compatible client

```bash
pip install 'posthog==7.67.0' openai
```

```python
import os
from posthog import Posthog
from posthog.ai.openai import OpenAI

posthog = Posthog(os.environ["POSTHOG_PROJECT_TOKEN"], host=os.environ.get("POSTHOG_HOST", "https://us.i.posthog.com"))
client = OpenAI(base_url="http://127.0.0.1:8000/v1", api_key="local", posthog_client=posthog)  # vLLM, llama-server, SGLang

resp = client.chat.completions.create(
    model="<served-model-name>",
    messages=[{"role": "user", "content": "ping"}],
    posthog_distinct_id="user_123",
    posthog_trace_id="trace-1",
    posthog_properties={"$ai_session_id": "conversation-abc", "$ai_provider": "vllm"},
)
posthog.shutdown()  # flush; required in short-lived or serverless processes
```

Ollama uses the same pattern with `base_url="http://localhost:11434/v1"` and `api_key="ollama"` (the docs example sets `$ai_provider` to `ollama`).

Per-call arguments: `posthog_distinct_id`, `posthog_trace_id`, `posthog_properties`, `posthog_privacy_mode`.

## Node

```bash
npm install @posthog/ai posthog-node openai
```

```typescript
import { OpenAI } from "@posthog/ai/openai";
import { PostHog } from "posthog-node";
const posthog = new PostHog(process.env.POSTHOG_PROJECT_TOKEN!, {
  host: "https://us.i.posthog.com",
});
const client = new OpenAI({
  baseURL: "http://127.0.0.1:8000/v1",
  apiKey: "local",
  posthog,
});
// per call: posthogDistinctId, posthogTraceId, posthogProperties, posthogPrivacyMode
```

Go and other languages have no wrapper: use OpenTelemetry (`references/otlp-and-gateways.md`) or manual capture.

## Manual capture (any language)

Send an `$ai_generation` event with the SDK's `capture`. Core properties: `$ai_trace_id`, `$ai_model`, `$ai_provider`, `$ai_input`, `$ai_input_tokens`, `$ai_output_choices`, `$ai_output_tokens`, `$ai_latency` (seconds), `$ai_base_url`, `$ai_http_status`, `$ai_is_error`, `$ai_stop_reason`, `$ai_time_to_first_token`. Add `$ai_span_id` and `$ai_parent_id` for nesting, `$ai_session_id` for conversations. The full list is in the Generations docs page.

## Identity

Events are per person. Pass a real `distinct_id` for users, or a stable service id. Use stable ids so server traffic does not create a new person per request.

## Read-only discovery

```bash
pip show posthog | grep -E '^(Name|Version)'
curl -fsS https://pypi.org/pypi/posthog/json | jq -r .info.version
curl -fsS https://registry.npmjs.org/@posthog%2fai/latest | jq -r .version
```
