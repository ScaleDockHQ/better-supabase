# 1116: Order tasks within lanes

- Status: accepted
- Date: 2026-11-21

## Context

Boards need a stable order that several callers change.

## Decision

`move_task` and `move_tasks` place a task before or after another within a stage. A refused move in `moveMany` is listed and the others apply. A stage-only `move` keeps the old update path.

## Alternatives considered

One ordering call per task was rejected for the round trips.

## Consequences

A rank clash is `TASK_RANK_CONFLICT`.
