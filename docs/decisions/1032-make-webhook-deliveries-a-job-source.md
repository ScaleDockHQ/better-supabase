# 1032: Make webhook deliveries a job source

- Status: accepted
- Date: 2026-11-15
- Amends: 0852, 0857

## Context

ADR 0857 left the blocks that only enqueue work, such as webhooks and reminders,
out of `jobs.get` because a queued message has no record to read (EX-1324).
Webhooks do keep one: the delivery log holds a row per delivery with its status,
attempt, response and last error, but no function returned a single delivery to
a client, so `dispatch` could only hand back an id.

## Decision

The webhooks module (version 8) adds `get_webhook_delivery(delivery uuid)`. It
returns one delivery as `jsonb`, or `null` for an unknown id, and checks the
caller as `redeliver_webhook` does: the service, or a member with
`webhooks.read` in the endpoint's tenant, otherwise `WEBHOOK_FORBIDDEN`. The
client adds `dispatchJob` and `redeliverJob`, which return `{ jobId:
"webhook:<id>" }`, and `jobs`, the `webhook` source. `pending` is `pending`,
`delivering` and `retrying` are `running`, `succeeded` is `completed` with the
delivery as `result`, and `dead` and `canceled` are `failed` with the hints
`WEBHOOK_DELIVERY_DEAD` and `WEBHOOK_DELIVERY_CANCELED`. The migrations are
`20270119000007_y4_get_webhook_delivery.sql` and the module data migration after
it.

## Alternatives considered

- Read the delivery table through PostgREST: it is granted only to adopters with
  tenant columns, and the client has no table transport.
- A new run table for every queue block: webhooks already have the record, so
  this adds nothing for them.

## Consequences

Webhooks are the first enqueue-only block with `jobs.get`. Reminders and the
other queue blocks have no per-message record yet; each needs its own record and
read function, so they stay open in EX-1324.

`get_webhook_delivery` is a security definer function, because clients have no
select grant on the delivery table; it checks the permission itself. That raises
the `webhooks` definer baseline in `tests/sql/practices-baseline.json` from 84
to 90 (one function across six generated variants).
