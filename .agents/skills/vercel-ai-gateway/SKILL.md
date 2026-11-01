---
name: vercel-ai-gateway
description: Operate Vercel AI Gateway (ai-gateway.vercel.sh), a hosted OpenAI-, Anthropic- and AI SDK-compatible endpoint with model fallbacks, provider routing, BYOK, budgets, logs and zero data retention. Use when the user mentions AI Gateway on Vercel, AI_GATEWAY_API_KEY, VERCEL_OIDC_TOKEN, `provider/model` slugs, providerOptions.gateway, vercel ai-gateway commands, or 402 quota_for_entity_exceeded and 429 errors. For other gateways use llm-gateway, litellm or cloudflare-ai-gateway.
license: MIT
compatibility: Needs a Vercel account or team, an AI Gateway API key in an environment variable or a 0600 file (or an OIDC token on Vercel), curl and jq; the Vercel CLI is optional. Ask the user before buying credits, enabling BYOK, setting budgets, creating or revoking keys, or enabling paid add-ons such as team-wide ZDR or trace drains.
metadata:
  author: ScaleDockHQ
  version: "0.1.0"
---

# Vercel AI Gateway

Use one hosted endpoint for hundreds of models: create a key, call it with OpenAI, Anthropic or AI SDK clients, set fallbacks and routing, cap spend with budgets, and clean up.

**Scope:** the hosted AI Gateway service at `https://ai-gateway.vercel.sh`, its API keys, OIDC, BYOK, budgets, routing rules, fallbacks, logs, privacy options and the `vercel ai-gateway` CLI. Out of scope: self-hosted gateways (`litellm`, `bifrost`, `llm-gateway`), the AI SDK itself, deploying apps on Vercel.

Work through the steps in order. Load a reference only when a step names it. Model slugs and rates change quickly, so list models live and read prices from the dashboard.

## Discover first

Read-only. Nothing here prints a key.

```bash
env | cut -d= -f1 | grep -E '^(AI_GATEWAY|VERCEL|ANTHROPIC|OPENAI)' || echo "no related env vars"
command -v curl jq vercel

# Public model catalog, no key needed
curl -sS https://ai-gateway.vercel.sh/v1/models | jq -r '.data[].id' | head -20

# With a key: credit balance and spend
curl -sS https://ai-gateway.vercel.sh/v1/credits -H "Authorization: Bearer $AI_GATEWAY_API_KEY" | jq .

# CLI view of keys and budgets (current scope)
vercel ai-gateway api-keys list && vercel ai-gateway budgets list
```

## Decision flow

1. No key: dashboard, CLI or API; on Vercel deployments prefer OIDC (`references/setup-and-auth.md`).
2. New code: AI SDK or the OpenAI Chat Completions or Anthropic Messages compatible endpoints (`references/api-and-sdks.md`).
3. Coding agent: `npx vercel@latest ai-gateway setup`, or set env vars by hand (`references/litellm-and-clients.md`).
4. Own provider credits or private data access: BYOK (`references/setup-and-auth.md`). BYOK spend is outside budgets.
5. Cost control: budgets at team, project, key or user level (`references/budgets-and-limits.md`).
6. Reliability: `providerOptions.gateway.models` fallbacks, provider `order`/`only`/`sort`, timeouts (`references/routing-and-fallbacks.md`).
7. Compliance: zero data retention, provider and model allowlists (`references/data-controls.md`).
8. Done: `references/teardown.md`.

## Rules

- **Ask before spending or storing.** Credits, BYOK, budgets, add-ons with per-request surcharges, trace drains.
- **Secrets never touch output.** `AI_GATEWAY_API_KEY` and BYOK provider keys come from env vars or `0600` files. API key values are shown once at creation.
- **Budgets are soft caps.** The request that crosses the limit still completes. Rejections are HTTP `402` with `type: quota_for_entity_exceeded`.
- **BYOK is not budgeted.** Spend through your own provider key is not counted against team, project or key budgets, and failed BYOK calls fall back to system credentials billed to your credits.
- **Keys die with their creator.** When a member leaves the team, their keys are deactivated. Use OIDC or team-attributed keys for shared automation.
- **Pin slugs, then verify.** Use `creator/model` slugs from `GET /v1/models`, not names from memory.
- **Never hardcode prices.** They change per model and provider.

## Workflows

### 1. Get a key

- [ ] `vercel ai-gateway api-keys create --name <name> --limit <n> --refresh-period monthly` -> `references/setup-and-auth.md`
- [ ] Save the key to a `0600` file at once; export `AI_GATEWAY_API_KEY`.
- [ ] Verify: `GET /v1/credits` returns JSON, not 401.

### 2. Call a model

- [ ] cURL or SDK against `https://ai-gateway.vercel.sh/v1` -> `references/api-and-sdks.md`
- [ ] Verify: the request shows in Logs in the dashboard (kept for 30 days of routing detail).

### 3. Route and fall back

- [ ] `models` array, `order`/`only`/`sort`, `providerTimeouts`, team routing rules -> `references/routing-and-fallbacks.md`

### 4. Cap spend

- [ ] Team and key budgets, defaults for new keys/projects/users -> `references/budgets-and-limits.md`
- [ ] Verify: an exhausted budget returns 402.

### 5. Privacy and compliance

- [ ] ZDR per request or team-wide, allowlists -> `references/data-controls.md`

### 6. Connect gateways and agents

- [ ] Claude Code, LiteLLM, OpenAI SDK -> `references/litellm-and-clients.md`

### 7. Tear down and troubleshoot

- [ ] Delete test keys, remove budgets and rules, stop add-ons -> `references/teardown.md`
- [ ] `references/troubleshooting.md`

## Reference index

- `references/setup-and-auth.md`: API keys, spend attribution, OIDC, BYOK, free vs paid tier.
- `references/api-and-sdks.md`: base URL, compatible APIs, REST endpoints, model listing.
- `references/routing-and-fallbacks.md`: fallbacks, provider options, timeouts, caching, routing rules.
- `references/budgets-and-limits.md`: budgets, defaults, alerts, rate limits.
- `references/data-controls.md`: ZDR, prompt training, allowlists, logs and trace drains.
- `references/litellm-and-clients.md`: Claude Code, LiteLLM, OpenAI SDK.
- `references/teardown.md`: clean up.
- `references/troubleshooting.md`: symptom to fix.

## Companion skills

- `llm-gateway`: gateway design across products. Install: `npx skills add ScaleDockHQ/llm-skills --skill llm-gateway`.
- `litellm`: self-hosted proxy. Install: `npx skills add ScaleDockHQ/llm-skills --skill litellm`.
- `cloudflare-ai-gateway`: Cloudflare's hosted alternative. Install: `npx skills add ScaleDockHQ/llm-skills --skill cloudflare-ai-gateway`.
- `llm-observability`: wider tracing and cost. Install: `npx skills add ScaleDockHQ/llm-skills --skill llm-observability`.
- `cloud-llms`: provider choice. Install: `npx skills add ScaleDockHQ/llm-skills --skill cloud-llms`.
