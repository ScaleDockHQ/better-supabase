---
"better-supabase": patch
---

Block docs pages and catalog entries now use the block names. The
`service-principals-table` UI recipe is now `service-accounts-table`, and the
old docs and recipe URLs redirect. The `idempotency`, `rate-limit` and
`webhook-inbox` blocks move from the developer category to automation, next
to `queue`, which ships them. Every block now has a docs page, including
`grants`, `mfa`, `subjects`, `reserved-slugs`, `jsonb-schemas`, `pgtap`,
`realtime-tables`, `rls-guard`, `permissions`, `sessions`, `impersonation`,
`read-sets` and `credentials`.
