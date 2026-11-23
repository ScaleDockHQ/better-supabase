---
"better-supabase": minor
---

`VersionStore.get` returns `{ version, at }` and `set(userId, version, at)` takes the time the version was read, so `createVersionCache` counts `maxStaleMs` from that time. Before, it dated a version taken from the shared store at the lookup, and a store whose keys never expire served a version of any age for another `maxStaleMs`, again and again. A store that still returns a number is read as a miss. `VersionStoreEntry` is exported from `better-supabase/server`. Breaking for a custom `store`; the 0.84 to 0.85 guide shows the new shape. See ADR 1226.
