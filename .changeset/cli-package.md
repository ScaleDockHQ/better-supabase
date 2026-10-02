---
"better-supabase": minor
"@better-supabase/cli": minor
---

The CLI moved to its own package, `@better-supabase/cli`, released at the same version as `better-supabase`. Install it with `pnpm add -D @better-supabase/cli`; the `better-supabase` command and its options are unchanged.

Breaking for `better-supabase`: the package no longer ships the `better-supabase` bin or the `better-supabase/cli` subpath. Import `run`, `registerCommand` and the introspection helpers from `@better-supabase/cli` instead. The new `better-supabase/sql` subpath exports the SQL kit (`renderKit`, `kitLayout`, `compileReadSets`), and `better-supabase/config` now exports the snapshot types, `DEFAULT_CLAIMS` and `tenantClaimPaths`.

The library no longer has `@supabase/config` as an optional peer; only the CLI reads `supabase/config.toml`.
