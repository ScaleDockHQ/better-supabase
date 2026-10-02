---
"@better-supabase/cli": patch
"better-supabase": patch
---

`better-supabase gen` uses `@supabase/postgrest-typegen` 0.3.1, which still produces the same `database.types.ts` as `supabase gen types` from Supabase CLI 2.119. Version 0.4.0 adds a `ComputedFields` key that the Supabase CLI does not emit yet, so it waits until the CLI catches up. The optional `@supabase/config` peer now accepts 0.11.
