---
"better-supabase": patch
---

The auth skill's PermDock caching recipe works as written. It passes only static tags to `bs.cached()`, then calls `cacheTag(snapshotTag(session.user.id))` and `cacheLife(cacheLifeFor(snapshot))` inside the loader once the snapshot is built, because the user id and the snapshot don't exist before `bs.cached()` returns. It pairs the recipe with `bs.invalidateSession(userId, { tags: [snapshotTag(userId)] })`.
