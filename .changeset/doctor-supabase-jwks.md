---
"better-supabase": minor
---

`doctor` checks `SUPABASE_JWKS`. BS509 reports an env file whose
`SUPABASE_JWKS` is not JSON or holds no key with a `kty`, which `loadEnv`
would reject. BS503 now also runs when the shell exports only `SUPABASE_JWKS`,
and warns that those inline keys override the running stack's
`SUPABASE_JWKS_URL`. The auth env page shows how to fill the variable with
`curl <url>/auth/v1/.well-known/jwks.json`.
