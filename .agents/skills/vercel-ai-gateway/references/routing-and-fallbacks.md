# Routing and fallbacks

> Verified against Vercel AI Gateway docs (models-and-providers pages), 2026-10-11

Sources: <https://vercel.com/docs/ai-gateway/models-and-providers/model-fallbacks>, `/provider-options`, `/provider-filtering-and-ordering`, `/provider-timeouts`, `/automatic-caching`, `/routing-rules`.

All options live in `providerOptions.gateway` and work across the AI SDK, Chat Completions, Messages and Responses formats.

## Model fallbacks

```ts
providerOptions: {
  gateway: {
    models: ["<fallback-1>", "<fallback-2>"];
  }
}
```

Tried in order when the primary model fails or is unavailable. Slugs come from `GET /v1/models`. Fallback usage is billed like any other request.

## Provider order, filter and sort

```ts
providerOptions: { gateway: { order: ['bedrock','anthropic'], only: ['bedrock','anthropic'], sort: 'cost' } }
```

`order` sets try order, `only` restricts providers per request at no extra cost (the team-wide provider allowlist is a paid add-on), `sort` ranks by `cost`, latency (`ttft`) or throughput (`tps`). Provider names must match the model's endpoint list.

## Provider timeouts

`providerTimeouts` (milliseconds, per provider) triggers fast failover when a provider is slow to start. It applies to BYOK credentials only. Some providers cannot cancel a stream, so you can still be billed for timed-out requests.

## Automatic caching

`caching: 'auto'` makes the gateway apply the provider's caching strategy, useful for providers that need explicit cache markers (the docs name Anthropic and MiniMax). Check the page for current providers and any pricing effects.

## Team routing rules

Team-wide model-level rules managed with the CLI:

```bash
vercel ai-gateway rules list --scope <team>
vercel ai-gateway rules add --type rewrite --source <creator/model> --destination <creator/other-model>
vercel ai-gateway rules add --type deny --source <creator/model>
vercel ai-gateway rules edit <rule_id> --disable
vercel ai-gateway rules remove <rule_id>
```

A rewrite serves the destination for requests naming the source; a deny returns `403`. Rules apply to every request in the team, so tell the user which apps are affected before adding one. Every subcommand takes `--format json`.

## Rate limits and 429

The gateway does not rate limit paid-tier traffic; the free tier has lower per-model limits; a 429 can come from the upstream provider with its own body. Honor `retry-after` when present and back off exponentially otherwise. The AI SDK retries 2 times by default.
