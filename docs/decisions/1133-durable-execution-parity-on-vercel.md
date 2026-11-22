# 1133: Add durable execution parity with additive hooks

- Status: accepted
- Date: 2026-11-21

## Context

Vercel Workflow, Queues and Schedules gained start options, bulk cancel, one-time schedules and
pause and resume. The installed `@workflow/world` 5.3.0 and `@workflow/core` 5.7.1 define
`start({ experimental_retention, experimental_hook, deploymentId })`, and an optional
`runs.cancelMany` and `events.createBatch` on the World. `@workflow/core` already falls back to
single-run cancels when a World has no `cancelMany`, and `world-postgres` implements neither
optional method. `@vercel/schedules` 0.0.3 has `get`, `enable`, `disable` and `invoke`, and a
`single` expression. Invariant 10 allows additive optional members on `apiVersion: 1`.

## Decision

`startFor` forwards `retention`, `deploymentId` and `hook`, and returns the owning run when a hook
start is refused with a `HookConflictError`. `cancelTenantRuns` in `src/workflow-sdk/cancel.ts`
lists a tenant's open runs through `analytics` and cancels them with `runs.cancelMany` or one by
one. We do not add `cancelMany` or `createBatch` to the Supabase World: the SDK falls back, and
`world.ts` carries the delivery contract changes of another pull request.

`ScheduleProvider` gains optional `scheduleOnce`, `enableSchedule`, `disableSchedule`,
`runScheduleNow` and `getSchedule`, mapped in `vercel-scheduler.ts` and checked by the conformance
kit when present. The SQL scheduler needs a migration for an enabled flag and a one-time row, so it
does not implement them in this change.

`cronRoute` takes `maxLateSeconds` and `overlap`. `maintenanceRoute` and `leaseOverlap` in
`src/blocks/queue/maintenance-route.ts` use them. The late guard reads `ce-vssscheduledat`, then
`ce-time`, because Vercel Schedules does not send `ce-time`.

## Alternatives considered

A new `apiVersion` for `ScheduleProvider`: rejected, since nothing breaks. Implementing
`cancelMany` in the World: rejected for the reason above. Guarding late runs with `ce-time` only:
rejected, Vercel does not send it.

## Consequences

Not built here: the outbox sink to Vercel Queues, and the `vercelQueueProvider` concurrency key,
trigger config and dead-letter writes. The SQL scheduler members and `events.createBatch` remain
open. Revisit the late guard if Vercel Cron starts sending a time header.
