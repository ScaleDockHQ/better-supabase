# 1184: Run before_task_close from a trigger on every closing path

- Status: accepted
- Date: 2026-11-22

## Context

`before_task_close` ran only from a direct call in `close_task`. A task closed by `update`, by a stage move into a completed or canceled stage, by a bulk set or by any other write skipped the hook, so a policy the hook enforced held for one of many paths. The call also sat inside the block that turns constraint errors into `TASK_ATTRS_INVALID`, so a hook that raised a check violation was reported as a bad stage.

## Decision

An after-update trigger on the tasks table fires once when `closed_at` goes from null to set, after the guard trigger has stamped it, and calls `before_task_close(task uuid, outcome text, note text)`. The outcome is `completed`, `failed` or `canceled`, taken from the close reason or the state. Templates are skipped. A hook that raises aborts the statement, so the close is refused with the hook's own error. The call in `close_task` is removed, and the handler there re-raises an error that carries no constraint name, so it maps only real table constraints to `TASK_ATTRS_INVALID`.

The hook no longer runs when `close_task` reopens a task with the outcome `open`, which it did before. Reopening is not a close. A task inserted already closed does not run it either.

## Alternatives considered

Calling the hook from each function that closes was rejected: new write paths would miss it again. A before trigger was rejected: the row is not closed yet, so the hook would see an open task.

## Consequences

One extra trigger on every task update, with a `when` clause that skips all but closing updates.
