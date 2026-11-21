---
"better-supabase": patch
---

Fix the Workflow World delivery contract. A continuation (the flow asked to wait) starts `attempt` over, so a long run no longer reaches `@workflow/core`'s 48 delivery cap through sleeps and step retries. In `vercel-queue` mode a continuation and the hops of a long delay are sent without an idempotency key, because Vercel drops a send whose key it saw in the last 24 hours. The World no longer claims `maxConcurrency` or `inBandFence` and creates spec 8 runs even when `WORKFLOW_SPEC_VERSION=9` is set, since the pgmq queue does not serialize a run's messages. `queueBatch` reports `retryable` as `@vercel/queue` returns it.
