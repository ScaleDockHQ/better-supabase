# 0843: Start inbox, outbox and queue work when it is written

- Status: accepted
- Date: 2026-11-13

## Context

Webhook inbox messages, outbox events and queue jobs waited for the next
cron or drain call, up to a minute on Vercel Cron. An app that wrote a row
and wanted it handled now had to call `process`, `relay` or `drain` itself
after each write, and rows written from SQL (triggers, `pg_cron`, the
incoming webhooks module) had no way to wake a worker at all.

## Decision

Two mechanisms, both optional, with the cron as the fallback:

- `kick: { waitUntil, run }` on `createQueue`, `createWebhookInbox` and
  `createOutbox` runs a pass after a successful `enqueue`, `enqueueOnce`,
  `replay`, `retryDead`, `store`, `receive` or `emit`. It is a second
  `withBlockHooks` layer outside the app's hooks, so it only observes the
  result (invariant 5). Writes made before a pass starts share it; a write
  made while a pass runs queues one more, so no row is missed. Next.js gets
  `bsb.waitUntil`, which wraps `after()`.
- The job modules add a statement-level `after insert` trigger
  (`bsb_notify_work`) on `webhook_inbox`, `outbox_events` and each queue
  table, which sends one `pg_notify('better_supabase_work', ...)` per
  statement that inserted rows. `listenForWork` in `better-supabase/postgres`
  listens on one pooled session connection, debounces the notifications,
  runs the matching pass, and asks the `*_has_work` probes after each
  (re)connect.

## Alternatives considered

- Row-level triggers: one notification per row. Postgres folds identical
  notifications within a transaction, but a bulk insert still pays a trigger
  call per row.
- Supabase Realtime instead of `LISTEN`: it needs the tables in the
  publication and still an always-on client, and it would expose job tables
  to a replication slot for a wake-up signal.
- Only the library hook: rows written from SQL would still wait for the cron.

## Consequences

Module versions: queue 13, webhook-inbox 11, outbox 7. On pgmq the trigger is
created by `index_job_queue`, which the module's data file runs for existing
queues. `listenForWork` throws for the transaction pooler (port 6543), which
drops `LISTEN`; `usesTransactionPooler` moved from the workflow World to
`better-supabase/postgres`. A `kick` after an `emit` inside an open
transaction finds nothing to relay, and the cron or the listener picks the
event up after the commit.
