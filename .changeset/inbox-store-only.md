---
"better-supabase": minor
---

`createInbox` accepts a source without `secrets` or `verify`, for an inbox that only `store()` fills because the sender is verified elsewhere (a chat or provider SDK). `store`, `process`, `list` and `purge` work as before, and `receive` throws a `TypeError` for such a source, so an unverified request is never stored.
