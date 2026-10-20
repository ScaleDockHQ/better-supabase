---
"better-supabase": minor
---

`vercelQueueBackend(client)` in `better-supabase/blocks/jobs` runs jobs on Vercel Queues. Pass a `PollingQueueClient` from `@vercel/queue` (new optional peer, `>=0.8 <0.9`). It passes `testQueueBackend`. Vercel Queues keeps no dead letters and has no schedules, so `schedule` still needs the SQL backend.
