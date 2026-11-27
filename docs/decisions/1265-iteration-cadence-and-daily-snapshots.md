# 1265: Iteration cadence and a daily snapshot

- Status: accepted
- Date: 2026-11-26

## Context

An iteration had a name and two dates. It had no number, no derived status
and no record of how the work moved during the cycle. Teams want a length,
a cooldown, a start weekday and a choice to roll open tasks forward.

## Decision

`iteration_cadences` stores that choice per team. `roll_iterations` is a
daily housekeeping job. It writes one `iteration_snapshots` row per active
iteration, records `iteration.started` on the start date and
`iteration.completed` the day after the end date, and clears a task snooze
that has passed. `iteration_burnup` reads the snapshots.
`get_iteration` adds a status (upcoming, active or completed) and a capacity,
the mean completed estimate of the three previous iterations.

## Alternatives considered

Computing the burnup from task history on every read would have scanned the
items for each day. A separate cycles module would have duplicated the
iteration row a task already points at.

## Consequences

The snapshot is one row per iteration per day, written by housekeeping.
Capacity is empty until three earlier iterations have completed work.
