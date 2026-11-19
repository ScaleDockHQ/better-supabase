---
"better-supabase": minor
---

API keys work without direct Postgres. `ServerOptions.apiKeyToken` mints a token for an API key's claims, and `apiKeyTokenSigner({ key })` from `better-supabase/server` signs them as a short-lived ES256 JWT with a P-256 key the project trusts (imported as a standby signing key). Without `postgres`, an API key's `ctx.db` and `ctx.supabase` then run over PostgREST with that token, under RLS and the key's scopes, with the tenant in `x-bsb-tenant`. `ctx.sql` is `undefined` for an API key without `postgres` instead of throwing, so the oRPC, Hono and MCP middleware no longer fail on it; reading `ctx.db` still throws without either option, and the error names both.
