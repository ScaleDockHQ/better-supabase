---
"better-supabase": patch
---

`better-supabase gen` uses `@supabase/postgrest-typegen` 0.4.0. `database.types.ts` gains a `ComputedFields` key on every table and view: the names of its computed fields, or `never`. postgrest-js reads it to leave computed fields out of `select('*')`, and row-typed function arguments no longer include them. Run `better-supabase gen` to regenerate. Supabase CLI 2.119 doesn't write `ComputedFields` yet, so until it does, `supabase gen types` output differs from `gen` by that key.
