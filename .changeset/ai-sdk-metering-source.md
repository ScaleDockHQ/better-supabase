---
"better-supabase": minor
---

`meterTelemetry` in `better-supabase/ai-sdk` records each row under the source `ai:<functionId>` (for example `ai:inbox.suggest-actions`) instead of `ai:telemetry`, and takes `idempotencyKey(event)`, `actor` and `metadata` options plus a function form of `source`. `rateLimitMiddleware({ rateLimit, scope, key, organizationId })` is a language model middleware that refuses a call before the model runs with a `rate_limited` error (code `AI_RATE_LIMITED`). Set `source: "ai:telemetry"` to keep the old source.
