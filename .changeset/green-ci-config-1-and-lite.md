---
"better-supabase": patch
---

Moves `better-supabase/client/lite` to `src/client/lite/index.ts` like every other subpath, lists `@supabase/auth-js` and `@supabase/realtime-js` as the peers it needs, and widens the `@supabase/config` peer range to `>=0.9.0 <2` (1.x loads on the current effect). A read whose `in` list the executor splits into chunks is no longer reported as truncated because the chunks together hold `maxRows` rows or more.

`db.$table(name)` and `withBetterResult` accept the tables a server loads on first use (`gen.serverTables: "lazy"`, the default), so `withBetterResult(db).customers.get()` works over a lazy schema.
