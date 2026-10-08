---
"better-supabase": minor
---

`better-supabase/credentials` resolves third-party tokens from a `credential_ref` instead of a token column. `vaultCredentials()` stores app and per-user secrets in Supabase Vault through the new `credentials` SQL module (service role only), caches tokens, and verifies inbound Standard Webhooks, HMAC and shared-secret requests. `createServer` takes a `credentials` provider and exposes it as `ctx.credentials`, and `subjectFor(ctx)` gives the user or app subject. `better-supabase/vercel-connect` adds `vercelConnectCredentials()` over Vercel Connect connectors, loading `@vercel/connect` on first use. `testCredentialProvider` checks other providers.
