---
"better-supabase": minor
---

`doctor --explain` now accepts a function name with `--args` and reports the share of time spent in
security definer helpers. New rules BS243 (a security definer function with a literal above 1 KB)
and BS244 (schema cache pressure) check the schema. The `updated-at` module adds
`better_supabase.memo_get` and `memo_set`, a value kept for one transaction, and BS206 points to
them. `gen.api.expose: "used"` and `gen.api.exposeAlso` wrap only the functions your sources call.
