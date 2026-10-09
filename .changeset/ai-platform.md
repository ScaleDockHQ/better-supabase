---
"better-supabase": minor
---

The `ai-cache` and `ai-providers` SQL modules cache model responses and keep each organization's provider keys, and `better-supabase/ai-sdk` meters model calls.

- `createAiCache` in `better-supabase/blocks/ai-cache` and `cacheMiddleware` in `/ai-sdk/cache` return a stored response or stream for a repeated call, per tenant with a TTL.
- `createAiProviders` in `better-supabase/blocks/ai-providers` keeps provider keys as `credential_ref` rows with batch and sandbox registries. `byokOptions` and `tenantGatewayOptions` turn them into AI Gateway BYOK options, `trackedSandbox` records sandboxes, and `aiBatches` in `/ai-sdk/batches` runs provider batches from a job.
- `meterTelemetry` records each call's tokens and cost on the tenant's usage meters, and `spendReconciliation` compares them with the AI Gateway spend report.
