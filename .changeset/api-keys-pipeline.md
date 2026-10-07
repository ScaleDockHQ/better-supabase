---
"better-supabase": minor
---

`withApiKey({ keys })` in `better-supabase/blocks/api-keys` is a `@supabase/server` pipeline entry for REST routes that take API keys: it verifies the key, answers a missing, invalid or rate-limited key with Problem Details, and contributes `ctx.auth` and the `withSupabase` keys (`jwtClaims`, `userClaims`, `authMode`) from the key's claims, so `withPostgresClient` and `withBetterPostgres` run queries as the key.
