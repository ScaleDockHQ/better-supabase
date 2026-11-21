# 1112: Lease task claims with epochs

- Status: accepted
- Date: 2026-11-21

## Context

Several workers pull from one queue and a crashed worker must not hold a task forever.

## Decision

A claims table holds one row per task with a token, a holder, an `epoch` and an expiry. `claim_task` takes or keeps a lease, `claim_next_task` takes the oldest ready task with `for update skip locked`, and `renew`, `release` and `delegate` need the token or the permission. An expired claim is lost and bumps the epoch on the next claim. `claim_next_task` and `move_tasks` carry an explicit read-only check, because their own bodies don't write. The claims table has a unique index on the task so an app-owned table can use `on conflict`.

## Alternatives considered

A column on the task row was rejected: it can't hold the token, epoch and profile and stays out of an adopted table.

## Consequences

A real concurrent claim can't be tested in the one-transaction harness; `skip locked` is covered by reading the SQL.
