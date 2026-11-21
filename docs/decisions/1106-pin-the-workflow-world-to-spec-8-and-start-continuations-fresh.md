# 1106: Pin the Workflow World to spec 8 and start continuations fresh

- Status: accepted
- Date: 2026-11-21

## Context

`@workflow/core` 5.7.1 fails a run when one queue message passes 48
deliveries (`MAX_QUEUE_DELIVERIES`; `WORKFLOW_MAX_QUEUE_DELIVERIES` can only
lower it). It reads the count from the `attempt` the World reports.
`createSupabaseWorld` added 1 to `attempt` on every `{ timeoutSeconds }`
answer, in `world.ts` and `vercel-delivery.ts`, so a run that sleeps or
retries a step more than 47 times through one message was failed by core.
`@workflow/world-postgres` 5.4.1 starts `attempt` over for a delayed
continuation of a spec 8 run or a step message, and carries it over only for
a spec 9 orchestrator message.

The World spreads the base World, so it also declared
`capabilities.maxConcurrency` and `capabilities.inBandFence` as
`@workflow/world-postgres` does. `maxConcurrency` says the queue delivers one
orchestrator message of a run at a time. The pgmq queue claims any number of
a run's messages at once and has no run delivery lease, so the claim was
false. With `inBandFence` on, `WORKFLOW_SPEC_VERSION=9` created spec 9 runs,
which also need counted redeliveries that the World does not implement.

In `vercel-queue` mode a continuation reused the idempotency key of the
message it continues. `@vercel/queue` documents that a send whose key it saw
within `min(retention, 24 hours)` is accepted and not delivered, so the
continuation was dropped whenever it came within a day of the first send.
This is confirmed from the installed package's documentation
(`SendOptions.idempotencyKey`); it was not run against a live Vercel
project. The same applies to the hops of a delay over 23 hours.

## Decision

- A continuation stores `attempt: 1`. A failed delivery still reports
  `attempt` as it was, so retries of one delivery stay counted.
- In `vercel-queue` mode a continuation and the hops of a split delay are sent
  without an idempotency key, as the reference World does. A redelivered
  callback can send a duplicate, which the runtime already tolerates.
- The World declares `maxConcurrency: false` and `inBandFence: false` and
  sets `specVersion` from `mintedSpecVersion()` without options, so it mints
  spec 8 whatever `WORKFLOW_SPEC_VERSION` says. Spec 9 stays readable: runs
  created elsewhere keep working.
- `sendBatch` results carry `retryable` from `@vercel/queue` when it reports
  one, and default to retryable otherwise.

## Alternatives considered

Enforcing both capabilities: a per-run lease and spec 9 attempt carry-over
belong to a queue redesign, which is larger than a drift fix. Keeping spec 9
behind the env var while declaring `maxConcurrency` off: core documents that
a World whose queue cannot serialize a run must leave it unset, and spec 9
runs lean on it for frequency, so that left a mode nobody tested.

## Consequences

Long runs no longer reach core's delivery cap through sleeps and retries.
Spec 9 is unavailable on this World until the queue serializes a run's
orchestrator messages; that is the reason to revisit this. Running
`@workflow/world-testing` in `poll`, `pg_net` and `vercel-queue` modes needs a
live stack and Vercel project, and is a manual step after this change.
