---
"better-supabase": minor
---

API keys have a `kind`. List the allowed kinds in `blocks.api-keys.options.kinds` (a check constraint enforces them) and pass `kind` to `create`. `create_api_key` takes `kind` as its last argument; the module's upgrade drops the old signature. `apiKeyResolver`, `apiKeyClaims` and `withApiKey` take a `claims(key)` hook that adds claims but cannot set `sub`, `role`, `aud` or `api_key`, and `serviceRoles` and `claims` receive the key with the `fields` columns.
