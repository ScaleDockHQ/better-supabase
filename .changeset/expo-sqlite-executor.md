---
"better-supabase": minor
---

Add `better-supabase/expo-sqlite`. `expoSqliteExecutor(db)` runs repository calls on a local expo-sqlite database without PowerSync, with the same SQLite compiler, exclusive write transactions on native and a UUID fallback for Hermes without `crypto`. With `addDatabaseChangeListener`, `watch()` and `useWatch()` rerun a call when its tables change.
