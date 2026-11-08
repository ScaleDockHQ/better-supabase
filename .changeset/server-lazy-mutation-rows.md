---
"better-supabase": minor
---

A plugin's `afterMutation` event copies the returned rows on the first read of `rows`, so a hook that reads only `keys` pays no copy.
