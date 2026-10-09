---
"better-supabase": minor
---

Add `better-supabase/tanstack-db`. `collectionOptions(betterSupabase, db, table, { query, queryClient })` returns options for `queryCollectionOptions()`: the collection loads through a `better-supabase/query` option, keys rows by the table's primary key, and runs inserts, updates and deletes through the repositories; the collection refetches after each write.
