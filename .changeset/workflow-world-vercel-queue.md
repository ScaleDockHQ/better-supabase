---
"better-supabase": minor
---

`better-supabase/workflow-sdk/world` delivers over Vercel Queues with `delivery: "vercel-queue"` (or `WORKFLOW_DELIVERY=vercel-queue`). `@vercel/queue` is an optional peer that the World loads on first use; it sends each message to its `__wkf_*` topic, splits delays over 23 hours into hops, and answers Vercel's retry with the World's backoff and the 73 delivery limit. New options: `deliveryHeaders` (`WORKFLOW_DELIVERY_HEADERS` or the Vault secret `workflow_delivery_headers`) adds headers such as `x-vercel-protection-bypass` to poll and `pg_net` deliveries, and `recoverAfter` (`WORKFLOW_RECOVER_AFTER_SECONDS`) sets how long an owed wake-up waits before the World queues it again.

Behaviour changes to check:

- The `workflow-sdk` SQL module is at version 8. Run `better-supabase upgrade`; its step only replaces `dispatch_workflow_deliveries()` and adds no table.
- In `pg_net` mode the World asks the database to dispatch as soon as it enqueues, so a delivery no longer waits for the next cron tick.
- The World clears `workflow_runs.wake_pending` when an orchestrator delivery completes and sweeps stale flags, in every mode.
- `delivery: "poll"` on Vercel logs a warning, because a function that has returned stops polling.
