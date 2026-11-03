# 0209: Start once on the run registry

- Status: accepted
- Date: 2026-11-03

## Context

`startOnce` relied on the Supabase World's `workflow_run_keys`. Any other World
only got a lookup of the `bsb.key` attribute, which two racing starts both
miss. Purging the World's runs also forgot the key, while `workflow_runs`
(the workflows block) keeps the run for its own retention.

## Decision

`workflow_runs` takes an `idempotency_key`, unique per tenant, and a
`dispatch_until` lease. `startOnce` with a `registry` records a queued run
whose `external_id` starts with `pending:`; `record_workflow_run` returns the
row that already holds the key, under an advisory lock. The caller that wins
`claim_workflow_run_dispatch` starts the run, then `set_workflow_run_engine`
writes the engine's id and ends the lease. When the World's own report already
mirrored the run, that row keeps its id, takes the key and the queued row's
attributes, and the queued row is deleted; a waiting caller records again to
find it. A lease that runs out can be claimed again, so a crashed starter delays
the run by one lease (60 seconds) and no more.

Without a `registry`, `startOnce` needs run keys and throws a typed error
otherwise. The `workflows` module also lets an app leave out schedules,
semaphores and start requests (`tables: null`) and add run columns
(`runExtraColumns`, with `fields` on `record`).

## Alternatives considered

- Deriving the key from the `bsb.key` attribute in the mirror trigger. A key
  reused after a World purge would hit the unique index inside the trigger and
  break the mirror.
- Keeping the best-effort fallback in `startOnce`. It hides the race the
  function exists to remove.

## Consequences

A registry start costs a record, a claim and a set. The run's engine id is
known only after `set_workflow_run_engine`, so a loser polls up to five
seconds. `record_workflow_run` gained trailing parameters; its 16-argument
call from the World mirror still resolves.
