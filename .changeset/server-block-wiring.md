---
"better-supabase": minor
---

`defineBlocks` checks the port wiring of its blocks once and keeps the resolved providers, so building a block client or `serviceBlocks` no longer runs the blocks by ports by blocks loop again.
