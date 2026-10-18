# 0038: Partition the event tables by month when an app opts in

- Status: accepted
- Date: 2026-10-18

## Context

The outbox, usage history, outgoing webhook deliveries and notification
delivery events only grow. Their purges delete row by row, which leaves dead
tuples, keeps autovacuum busy and holds locks on large tables. The audit log
already has an opt-in `partitioned` option (ADR 0034) that partitions it by
month and drops whole months past retention. The same shape fits these tables.

A partitioned table can't have a unique index that leaves out the partition
key, and Postgres can't convert an existing table in place.

## Decision

`blocks.outbox`, `blocks.usage` (with `options.history`), `blocks.webhooks`
and `blocks.notifications` take `options.partitioned`, off by default. With it
on, a new managed table is `partition by range` on its timestamp, with a
primary key of `(id, <timestamp>)`, a `<table>_default` partition, and
monthly partitions from `MONTHLY_PARTITIONS` and `registerPartitions` in
`src/sql/shared.ts`:

| Block           | Table                          | Key                 |
| --------------- | ------------------------------ | ------------------- |
| `outbox`        | `outbox_events`                | `(id, created_at)`  |
| `usage`         | `usage_history`                | `(id, recorded_at)` |
| `webhooks`      | `webhook_deliveries`           | `(id, created_at)`  |
| `notifications` | `notification_delivery_events` | `(id, created_at)`  |

The purge drops every month wholly before `ctx.cutoff`, which is the most
conservative data-lifecycle retention and null under any legal hold, through
`expired_partitions`, then deletes the remaining rows as before. The outbox
keeps a month that an active consumer hasn't passed yet, and webhooks keep a
month that holds a delivery the row purge would keep.

Uniqueness the old indexes gave now comes from a transaction-scoped advisory
lock and a lookup: the outbox `key` per tenant in `emit_event`, the
`(endpoint, event)` pair in `publish_webhook_event` and `dispatch_webhook`,
and the `provider_event_id` in `record_delivery_event`. The identity columns
of the outbox position and the usage history id become sequences, which work
on every supported Postgres version for partitioned tables.

For notifications, only the leaf `notification_delivery_events` is
partitioned. Events, recipients and deliveries are referenced by `id` alone
and updated in place, and recipients and deliveries are leased by id; a child
would have to carry its parent's `created_at` in every foreign key and every
lease. A delivery event always comes after its notification, so dropping a
month past every tenant's notification retention never drops an event whose
notification the purge keeps.

Doctor rule BS335 reports a table whose block has the option on but whose
primary key is `id` alone.

## Alternatives considered

- Partitioning by default. Most apps never reach the size where it pays off,
  and a partitioned table gives up unique indexes on its own columns, so the
  default stays a plain table.
- Converting existing tables in place. Postgres can't, and a copy in a
  migration would lock a large table for its whole run. The option applies to
  new tables only; doctor names the ones created before it.
- Partitioning every notification table with composite foreign keys. It
  doubles every key the leases and the API use, for tables that the purge
  already deletes by notification.

## Consequences

An app that turns the option on for a new install gets purges that drop whole
months and indexes that stay small. An app with an existing table has to copy
its rows into a partitioned table in a maintenance window, or keep the option
off. `maintain_partitions()` has to run from cron so future months exist;
rows outside them land in the default partition. Revisit this if Postgres
gains global unique indexes on partitioned tables.
