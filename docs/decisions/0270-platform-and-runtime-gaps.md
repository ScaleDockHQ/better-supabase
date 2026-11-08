# 0270: Close the platform and runtime gaps of the base layer

- Status: accepted
- Date: 2026-11-07
- Amends: 0252

## Context

Part 5 of the declarative base layer plan lists the platform and runtime items
an app wrote beside the blocks. An audit found the comments avatar
(`list_comments` returns it with profiles), imports without events
(`events: "skip"`) and the outbox subject on app tables (`subjectType`,
`subjectId`) already shipped. Three were open as code, and one is deliberately
left.

## Decision

- Notifications: `options.resolveAddress` names an app function
  `schema.name(user uuid, channel text) returns text`. Claimed deliveries,
  claimed digests, the suppression join and the suppression of a bounced address
  use its answer and fall back to `auth.users.email` when it returns null. The
  plan's `resolveAddress` takes no arguments; a user and a channel are the least
  an address depends on.
- Realtime triggers are static statements. `config.realtime.tables` and the
  tables of a block entity with `subject.realtime` now render `create trigger
  bsb_realtime_insert`, `_update` and `_delete` (or `bsb_realtime` without a
  scope column) in the schema file, as row audit does (ADR 0252), instead of
  `select track_realtime(...)`, which a schema diff skips. A module installed
  before `realtime-tables` in a rerunnable layout keeps the call in its data
  file, because the trigger function does not exist yet. `track_realtime` stays
  for hand use.
- Workflows: `workflow_opt_outs` is an optional table. Mapped to null, the
  block leaves out the table, `set_workflow_opt_out` and the opt-out check. The
  grants table stays required: a restricted definition needs its rows.

The notifications options schema ships in the client bundle through the block
manifest, and the next-build baseline never grows. The new `resolveAddress`
entry cost 28 bytes on every route, so the spec defaults of `createdEvent`,
`updatedEvent` and `realtime` are gone: the SQL module already falls back to the
same values (`notification_created`, `notification_updated`, `broadcast`), so
only the documented default in the JSON Schema is lost.

## Not done

- A separate drive grants mode. `options.roleFunctions` already lets the app or
  the authorization provider answer the role on a node or a drive, and the
  block's own grants stay for sharing links and lists. Dropping the grants table
  would change the sharing, offboarding and access audit functions (more than
  sixty statements), so it needs its own decision.

## Consequences

An app with its own address table deletes its join in a notifications wrapper.
An app that called `track_realtime` in a migration for a configured table can
delete the call: the schema file owns the trigger.
