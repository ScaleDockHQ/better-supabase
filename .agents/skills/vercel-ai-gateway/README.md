# Vercel AI Gateway

Helps an agent use Vercel AI Gateway: create API keys or use OIDC, call hundreds of models through OpenAI, Anthropic or AI SDK clients, configure fallbacks and provider routing, bring your own provider keys, set budgets, enforce zero data retention, wire up Claude Code and LiteLLM, and clean up.

## Install

```bash
npx skills add ScaleDockHQ/llm-skills --skill vercel-ai-gateway
```

## Rules

- **Ask before spending or storing.** Credits, BYOK, budgets, paid add-ons.
- **Never print keys.** Read them from environment variables or `0600` files.
- **Budgets are soft and exclude BYOK.** Add provider-side limits for BYOK.
- **Use live slugs and rates.** List models from the API; never hardcode prices.
- **Prefer OIDC on Vercel.** Keys are tied to their creator.

## References

- [`references/setup-and-auth.md`](references/setup-and-auth.md): keys, attribution, OIDC, BYOK, tiers.
- [`references/api-and-sdks.md`](references/api-and-sdks.md): base URLs, REST endpoints, SDKs.
- [`references/routing-and-fallbacks.md`](references/routing-and-fallbacks.md): fallbacks, provider options, rules.
- [`references/budgets-and-limits.md`](references/budgets-and-limits.md): budgets and rate limits.
- [`references/data-controls.md`](references/data-controls.md): ZDR, allowlists, logs, trace drains.
- [`references/litellm-and-clients.md`](references/litellm-and-clients.md): Claude Code, LiteLLM, OpenAI SDK.
- [`references/teardown.md`](references/teardown.md): clean up.
- [`references/troubleshooting.md`](references/troubleshooting.md): symptom to fix.

## Companion skills

- `llm-gateway`, `litellm`, `cloudflare-ai-gateway`: other gateways.
- `llm-observability`, `cloud-llms`: tracing and provider choice.

## License

MIT
