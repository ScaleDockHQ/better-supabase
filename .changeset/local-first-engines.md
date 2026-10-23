---
"better-supabase": minor
---

PowerSync, SQLite and TanStack DB run as engines behind the generated data hooks. `powersyncEngine(powersync, { connector, local })` from `better-supabase/powersync`, `sqliteEngine(database)` from the new `better-supabase/sqlite` (Expo SQLite through `expoSqliteDatabase`, Supabase Lite through `liteDatabase`) and `tanstackDbEngine({ collections })` from `better-supabase/tanstack-db` go to `createClient` or `createNativeClient`, so native screens read `useCustomers(...)` like web screens. With a device engine, `bsb.db` runs on the local database for the tables in `local` and on PostgREST for the rest. `useSyncStatus()` and `useConflicts()` move to `better-supabase/react` and read the engine.

`memoryEngine` and `queryEngine` take `live`, a change feed such as `realtimeChanges(betterSupabase, supabase)` from `better-supabase/realtime`, and `tables` to map a hook name to its tables. `where` on every hook and repository takes a filter tree from a list query or saved view, checked against the filterable columns.

Breaking: `better-supabase/powersync/react` (`useWatch`), `better-supabase/expo-sqlite` (`expoSqliteExecutor`) and `better-supabase/tanstack-db/supabase` (`supabaseCollection`) are removed, along with `watch` and `sqliteTables`, and `@supabase-labs/tanstack-db` is no longer a peer. Doctor reports what is left as BS418. See the 0.14 to 0.15 guide.
