# 1161: Let a task hold open an approval

- Status: accepted
- Date: 2026-11-21

## Context

ADR 1114 added holds that wait on a person. The brief also asked for a hold that waits on a decision: with the approvals block installed, deciding releases or cancels the task. `time-entries-approvals.ts` shows the pattern: the block files a request with `open_approval`, and the approvals module calls back into the block with the decision.

## Decision

`blocks.tasks.options.hold.approval` (`true`, or `{ policy, onReject }`) makes `hold_task` open an approval of the subject type `task_hold` for the task. The default policy has one step whose approvers hold the manage permission. `policy.run` is refused, because the decision itself releases or cancels the task. The tasks module contributes to approvals (`filedBy: "block"`, `access: "declared"`): approving calls `settle_task_hold(task, 'release')`, and a rejection calls it with `'cancel'` unless `onReject` is `keep`. `approvable` is true only while the task is on hold. `settle_task_hold` is `security definer` and revoked from every role, so a decider needs the approval and not the write permission. It moves a task to the first canceled stage of its pipeline through the normal stage trigger, which also clears the hold. The option needs the approvals block and the `held_at` column and throws at render otherwise. `task.held` carries `approvalId`.

Without the option nothing changes: the tasks module output, its contract and its goldens stay as they were. The module lists `approvals` in `integrates`.

## Alternatives considered

An `approval` argument on `hold_task` was rejected: it changes a published function signature and every client for a choice an app makes once. A hold that always asks was rejected: most holds wait on a person.

## Consequences

A rejected hold cancels the task by default, so an app that wants a second try sets `onReject: "keep"`. A manual `release_task_hold` leaves the request pending, and a later hold of the same task could meet the older request's decision. Cancelling the request on release would close that gap and is left for a follow-up.
