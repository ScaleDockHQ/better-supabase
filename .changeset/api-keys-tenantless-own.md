---
"better-supabase": minor
---

A personal API key without a tenant acts in every tenant its user belongs to, so `create_api_key` now needs the `own` permission in each of those tenants and refuses the key with `API_KEY_FORBIDDEN` otherwise. Before, it skipped the check, so a role without `api_keys.own` could still create a key for all its tenants. `sql upgrade` moves the module to version 3.
