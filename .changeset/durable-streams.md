---
"better-supabase": minor
---

`better-supabase/streams` stores resumable output for chats, workflows and agents. The `streams` SQL module keeps ordered chunks with idempotent appends, a cancel flag the writer reads on its next append, owner reads through RLS and a Realtime ping per stream; `postgresStreamStore`, `teeToStore`, `writeToStore` and `resumeFromStore` use it. `better-supabase/streams/redis` adds `redisStreamStore`, which takes a node-redis client or a `url` (the new optional peer `redis` is loaded on first use). `testStreamStore` in `better-supabase/testing` checks other stores.
