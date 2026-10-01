---
"better-supabase": minor
---

`next.cached()` takes `tags` and `life.stale`. `tags` adds cache tags to the entry next to `bs:session:<user id>`, and `life.stale` caps the stale time `sessionStale` computes, so `next.cached({ tags: [snapshotTag(sub)], life: cacheLifeFor(snapshot) })` caches a PermDock snapshot no longer than the token or the snapshot. `next.invalidateSession(userId, { tags })` also expires the extra tags. PermDock can now drop the "Planned in better-supabase" note in its `guides/next-cache-components.mdx`.
