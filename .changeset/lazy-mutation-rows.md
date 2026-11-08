---
"better-supabase": minor
---

A write whose only `mutation` listener is the cache adapter no longer copies the returned rows: `MutationNotice.rows` is copied on the first read.
