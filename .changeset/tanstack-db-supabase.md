---
"better-supabase": minor
---

`better-supabase/tanstack-db/supabase` adds `supabaseCollection(betterSupabase, supabase, table, options)`, a TanStack DB collection on `@supabase-labs/tanstack-db` (a new optional peer, `>=0.1.0 <0.2`). Live queries load on demand through PostgREST, `realtime: true` keeps them current through `postgres_changes`, and inserts, updates and deletes go through the table's repository, so RLS, hooks, events and plugins apply. `writes: "direct"` keeps the package's own handlers. It needs `casing: "snake"` and tables in the `public` schema; `collectionOptions()` from `better-supabase/tanstack-db` stays the choice for camel casing.
