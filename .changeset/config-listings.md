---
"better-supabase": minor
---

Add `better-supabase config actions` and `better-supabase config policies`, with `listActions()` and `listAccessPolicies()` in `better-supabase/sql`. `config actions` lists every block, record type, bucket and topic action with the permission key it resolves to and whether the config, the provider or the default named it. `config policies` lists the policies the `@bsb access` tags render, one row each, and the generated SQL now comes from the same rows. Both print JSON with `version: 1` and ship a JSON Schema.
