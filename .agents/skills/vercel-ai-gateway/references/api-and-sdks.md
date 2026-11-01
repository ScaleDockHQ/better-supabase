# API and SDKs

> Verified against Vercel AI Gateway docs (rest-api, openai-compat, anthropic-compat pages), 2026-10-11

Sources: <https://vercel.com/docs/ai-gateway/sdks-and-apis>, `/sdks-and-apis/rest-api`, `/sdks-and-apis/openai-chat-completions`, `/sdks-and-apis/anthropic-messages-api`, `/sdks-and-apis/responses`, `/models-and-providers`.

## Base URLs

| API                       | URL                                                                       |
| ------------------------- | ------------------------------------------------------------------------- |
| OpenAI Chat Completions   | `https://ai-gateway.vercel.sh/v1` (`POST /v1/chat/completions`)           |
| Anthropic Messages        | `https://ai-gateway.vercel.sh` (`POST /v1/messages`)                      |
| Responses / OpenResponses | `https://ai-gateway.vercel.sh/v1`                                         |
| AI SDK                    | `ai` package; plain `provider/model` strings route through the gateway    |
| Claude Code               | `https://ai-gateway.vercel.sh/claude-code` (see `litellm-and-clients.md`) |

Auth: `Authorization: Bearer $AI_GATEWAY_API_KEY` (or an OIDC token). Models are `creator/model` slugs.

```bash
SLUG="$(curl -sS https://ai-gateway.vercel.sh/v1/models | jq -r '.data[0].id')"   # pick a real slug first
curl -sS https://ai-gateway.vercel.sh/v1/chat/completions \
  -H "Authorization: Bearer $AI_GATEWAY_API_KEY" -H "Content-Type: application/json" \
  -d "$(jq -n --arg m "$SLUG" '{model:$m,messages:[{role:"user",content:"ping"}],max_tokens:16}')" | jq '.choices[0].message.content'
```

Gateway-specific fields (`providerOptions`) are extension fields: the OpenAI SDK types do not include them, so spread them into the request body.

## REST endpoints

| Endpoint                                     | Purpose                                                      |
| -------------------------------------------- | ------------------------------------------------------------ |
| `GET /v1/models`                             | all models; add `?include_availability` for team annotations |
| `GET /v1/models/{creator}/{model}/endpoints` | every provider endpoint serving a model, with pricing        |
| `GET /v1/credits`                            | credit balance and total spend                               |
| `GET /v1/generation`                         | cost, latency and tokens for one generation                  |
| `GET /v1/report`                             | aggregated spend reports for the team                        |

`/v1/models` answers without a key. The free-tier model list is on the dashboard models page with the free-tier filter.

## AI SDK

Use `generateText({ model: "creator/model", prompt })`; set `providerOptions: { gateway: {...} }` for routing. Authentication is `AI_GATEWAY_API_KEY` or OIDC. The docs examples target AI SDK 7 and a Python beta; check your installed version against the AI SDK docs.

## Differences to remember

- Dynamic provider choice: unless you set `order`/`only`/`sort`, the gateway chooses providers itself.
- Reasoning, tools, structured output and images vary per model; check the model page or `/endpoints` before relying on one.
- Free-tier requests are rate limited per model; paid tier is not limited by the gateway.
