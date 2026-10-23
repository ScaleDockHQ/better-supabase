# 0048: App tables emit outbox events from a database trigger

- Status: accepted
- Date: 2026-10-19

## Context

Rules (ADR 0046) and the workflow builder start from events, but an app
table's rows changed without telling anyone. No-code builders (Airtable,
Baserow, Teable) run automations on "record created" and "record updated",
and apps here had to write the same trigger by hand for every table. Events
emitted from TypeScript miss the writes that go through PostgREST, the SQL
editor or another service.

## Decision

`appTables.<name>.events` (`true` or `{ on, include }`) renders an
`after insert or update or delete` trigger, `bs_emit_event`, that calls the
security definer function `better_supabase.<name>_emit_event()`. The function
writes one row to the outbox through `ctx.emit`, in the same transaction as
the write. The event type is `<subject type or table name>.<created|updated|deleted>`,
the subject is `<table>/<id>` and the tenant is the scope column. The payload
holds the id, the tenant and subject ids, the columns in `include` and, for an
update, the names of the changed columns. An update that changes only
`updated_at` emits nothing.

The table needs the outbox block; the renderer refuses the config without it.
`gen blocks` writes `appTableEvents`, a typed event map over
`AppTableEventData`. Delivery stays with the outbox consumers:
`createRuleSink` runs the rules for each event and dispatches the actions.
`WorkflowBuilder.sink()` started the workflows whose trigger matched until
ADR 0093 removed event triggers; an automation's `workflow` action starts
them now.

Rules get four built-in actions next to `approvals`: `notify`, `setField`,
`webhook` and `workflow`. Each is a factory over a structural interface, so
the rules block imports no other block.

## Alternatives considered

Emitting from the repository layer would miss writes that don't go through
it. Logical replication or Supabase Realtime sees every write, but it isn't
transactional with the outbox and needs a long-running listener. A generic
trigger that reads the table config at run time would need a config table in
the database; rendering one function per table keeps the SQL readable and the
payload columns fixed at migration time.

## Consequences

Every insert, update and delete on a table with events writes one outbox
row, so a bulk import writes one event per row. The payload carries only the
columns in `include`, so a consumer that needs more reads the row. Changing
`events` is a safe design change (`table.events`), and a design with `events`
is format 4.
