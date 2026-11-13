---
"better-supabase": minor
---

Inbox messages, outbox events and queue jobs can start as soon as they are written instead of on the next cron call. `createQueue`, `createWebhookInbox` and `createOutbox` take `kick: { waitUntil, run }`, which runs a pass after each successful write (`bsb.waitUntil` in Next.js wraps `after()`). The queue, webhook-inbox and outbox modules (versions 13, 11 and 7) add a statement trigger that notifies `better_supabase_work` on each insert, and `listenForWork(pool, { inbox, outbox, queues })` in `better-supabase/postgres` runs the matching pass on a long-lived Node process, including for rows written from SQL. Run `better-supabase upgrade`. `usesTransactionPooler` is now also exported from `better-supabase/postgres`.
