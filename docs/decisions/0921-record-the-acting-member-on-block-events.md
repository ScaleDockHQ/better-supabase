# 0921: Record the acting member on block events

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0056 made the audit trigger and `track_actor` name the member a server write acts for, and the `act` claim stamps the admin on audited rows. A block method that records only an event (most of them) named the impersonated user as `actorId` and lost the admin behind the session, because only `support_session.*` events carried one (EX-1321).

## Decision

`emitBlockEvent` fills `BlockEventMeta.impersonatedBy` from `meta.context.actor.impersonator` unless the block names it. `blockCloudEvent` and the row mutation events add it to `data.impersonatedBy` next to `actorId`, and `auditEventOf` maps `data.impersonatedBy` to the audit entry's `impersonatedBy` for every event type. The SQL stays as it is: the audit function still refuses a caller-supplied `impersonatedBy` when the token has an `act` claim, and the sink runs with the service role, so the value is the one the server read from the verified session.

## Alternatives considered

An `impersonated_by` column on every block table needed a migration for each block and still left events without the admin. A SQL trigger on every table duplicated the audit trigger's job.

## Consequences

Every block that emits events records the acting member by default, in webhooks, sinks and the audit log. A block whose methods emit no event (the `emits: false` list) still relies on the audit trigger. An event handler that rebuilds a block event by hand has to copy `impersonatedBy`.
