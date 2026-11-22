# 1182: Limit hold kinds and cancel the approval a hold leaves behind

- Status: accepted
- Date: 2026-11-22

## Context

A hold takes any short lowercase kind, and with `hold.approval` every kind filed an approval request. An adopter wants some kinds, such as a question for a person, to skip the approval. A pending request also stayed open when the hold ended without a decision: `release_task_hold`, the guard that releases a task which leaves the hold stage, and closing the task all left it pending, so an approver could still see and decide a hold that no longer existed.

## Decision

`hold.kinds` is an allowlist of kinds; any other kind raises `TASK_HOLD_INVALID`. `hold.approval.kinds` lists the kinds that open an approval and must be a subset of `hold.kinds` when both are set, otherwise config resolution fails. Without either option nothing changes. The `hold_task` signature is unchanged.

Every path that ends a hold without a decision cancels the pending request of the `task_hold` subject by updating the approval request to `cancelled`, the way `withdraw_timesheet` does: `release_task_hold`, the guard trigger (hold stage left, task closed). `task.hold_released` carries `approvalCancelled` from `release_task_hold`. A decision that already settled the request is not touched, and `settle_task_hold` is unchanged.

## Alternatives considered

Calling `cancel_approval` was rejected: it allows only the requester, a manager or the service role, and a task writer releasing a hold is none of those.

## Consequences

A cancelled request writes no `approval.cancelled` event, as with timesheet withdrawal. The `task.hold_released` event is the record.
