# 0214: Keep claimable leases in the queue block

- Status: accepted
- Date: 2026-11-03

## Context

The `idempotency` module has `acquire_lease`, `extend_lease` and
`release_lease`. They answer only held or not held, so a caller that wants
"run this once, ever, for a day" has no way to see that the work already
finished, and `withLease` has no wait: a busy lease returns at once. Drains
that share a key (one import per file, one run per tenant) need a bounded wait
that fits inside the drain's `budgetMs`. `startRegistered` in
`src/workflow-sdk` also left its dispatch claim in place when `launch()`
threw, so the next caller waited out the 60 second lease, where `startKeyed`
released its key.

## Decision

The `queue` SQL module (version 9 to 10) adds the `job_leases` table and four
service-only functions: `claim_lease(scope, key, lease_seconds)` answers
`claimed`, `busy` (with `retry_after_ms`) or `completed`; `complete_lease`
keeps a finished lease for `keep_seconds`; `extend_lease_claim` and
`release_lease_claim` act only for the current holder. The two verbs that the
idempotency functions already use are `extend_lease_claim` and
`release_lease_claim` here, because overloads with the same argument names
cannot be called through PostgREST. The upgrade step needs no SQL: the table
and functions use `create ... if not exists` and `create or replace`.

`createLeases(source)` in `src/blocks/queue/leases.ts` has `claim` (retries
with backoff up to `timeoutMs`, then returns a typed `busy`) and `withLease`
(extends while the callback runs, releases when it throws, completes with
`completeFor`). The older `withLease` helper keeps working on the idempotency
functions.

`startRegistered` ends its dispatch claim when `launch()` throws, by recording
the row's own pending id through `setEngine`, which clears `dispatch_until`.
No new SQL is needed for it.

## Alternatives considered

- Extend `acquire_lease` with a completed state: it belongs to a block that
  has nothing to do with queues, and its holder flow differs.
- Name the new functions like the old ones and overload them: PostgREST can't
  choose between overloads with the same argument names.
- Add a `release_workflow_run_dispatch` function: it changes the `workflows`
  module for what `setEngine` already does.

## Consequences

Completed rows stay in `job_leases` until the same key is claimed again; a
purge job can follow if tables grow. Fixtures, the SQL golden files and the
example's generated modules need regeneration after this change.
