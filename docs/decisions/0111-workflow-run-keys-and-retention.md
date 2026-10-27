# 0111: Claim Workflow SDK start keys in a table and purge ended runs in SQL

- Status: accepted
- Date: 2026-10-27

## Context

`startFor` made a start idempotent by listing runs with the `bsb.key`
attribute before it started one. Two starts that race both find nothing and
both start a run, so a double-clicked button or a webhook delivered twice ran
the workflow twice. The World's tables in the `workflow` schema also grow
without bound: every run keeps its events, steps, waits, stream chunks and
hooks after it ends, and the Workflow SDK has no retention of its own for a
Postgres World.

## Decision

`workflow.workflow_run_keys` holds one row per key. `workflow_claim_run_key`
inserts the key, or takes over a claim older than five minutes that never got
a run, and answers whether the caller won and which run the key has.
`startFor` claims the key when the World has `runKeys`, starts the run, then
records its id with `workflow_set_run_key`; a start that fails frees the key
with `workflow_release_run_key`. A start that lost the claim polls until the
run id appears. Runs started before the table existed are still found by
their attribute.

`workflow_purge_runs(older_than, statuses, batch)` deletes ended runs and
their rows in batches with `for update skip locked`, and refuses a status
that has not ended. The block's `retention` option schedules it hourly with
pg_cron; `db prune-workflows` and `world.purgeRuns` run it on demand.
`workflow_open_hooks` lists the hooks of open runs without their tokens.
All four are security definer functions only the service role may call.

## Alternatives considered

- A unique index on the `bsb.key` attribute of `workflow.workflow_runs`. The
  table follows world-postgres's DDL, which we regenerate from upstream, and
  the losing start would fail with a constraint error from inside the SDK
  instead of getting the first run back.
- An advisory lock around the lookup and the start. It only holds while one
  connection stays open, and `start` goes through the World's own pool.
- Deleting through the Workflow SDK API. It has no bulk delete for runs, and
  deleting row by row over HTTP is much slower than one statement per batch.

## Consequences

A keyed start costs two more statements. A start that crashes between the
claim and the run holds the key for five minutes, and a concurrent start
waits up to five seconds before it gives up. Purged runs are gone from the
World; the copies in `workflow_runs` follow the workflows block's own
retention.
