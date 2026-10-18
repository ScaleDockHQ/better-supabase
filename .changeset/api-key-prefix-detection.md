---
"better-supabase": minor
---

A Bearer token that starts with the API key prefix and `_` now counts as an API key even when the rest is malformed. `apiKeyResolver` and `withApiKey` verify it, and `verify` answers `invalid`, so `bs_bad_key` gets `INVALID_API_KEY` like a revoked or unknown key instead of `API_KEY_REQUIRED` or a JWT error. `createApiKeys` returns `isApiKey(token)` for code that routes a Bearer token to either API key or JWT verification. A `keys` object without `isApiKey` keeps the old rule.
