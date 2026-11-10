---
"better-supabase": patch
---

`createVersionCache` keeps at most `maxEntries` users in process (default 10,000) and drops the least recently used one first, so a long-lived server no longer holds one entry per user it has ever seen. `BlockSet.client(db, key)` without options now shares one block builder per `db`, so repeated calls wire the port graph once.
