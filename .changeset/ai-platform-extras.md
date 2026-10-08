---
"better-supabase": minor
---

The `ai-cache` SQL module and `createAiCache` in `better-supabase/blocks/ai-cache` store model responses per tenant with a TTL and a purge job. `cacheMiddleware` in `better-supabase/ai-sdk/cache` wraps a language model with `wrapLanguageModel`, returns a stored response for a repeated call and replays a stored stream with `simulateReadableStream`.

The `ai-providers` SQL module and `createAiProviders` in `better-supabase/blocks/ai-providers` keep each organization's provider keys as `credential_ref` rows, revoked when a key is replaced or the tenant is removed, together with a batch registry and a sandbox registry. `byokOptions` and `tenantGatewayOptions` in `better-supabase/ai-sdk` turn a tenant's keys into AI Gateway BYOK options, and `trackedSandbox` records sandboxes so `idleStopJob` stops the idle ones. `aiBatches` in `better-supabase/ai-sdk/batches` starts provider batches for a tenant, polls them from a job and stores their results.

`meterTelemetry` in `better-supabase/ai-sdk` records each model call's tokens and cost on the tenant's usage meters through `registerTelemetry`, and `spendReconciliation` compares them with the AI Gateway spend report every night.
