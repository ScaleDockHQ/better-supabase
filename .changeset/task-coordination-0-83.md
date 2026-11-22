---
"better-supabase": minor
---

Close five gaps in the task coordination, with the old and new forms in the [0.82 to 0.83 guide](https://bettersupabase.com/docs/migration/0.82-to-0.83). Run `better-supabase upgrade`: the `tasks` module is at version 7.

- `claimNext` picks only tasks assigned to the caller. Set `claims.next: "any"` to keep the old pick. Agent sessions always pick assigned tasks (`TASK_NOT_ASSIGNED`, `TASK_FILTER_FORBIDDEN`).
- `hold.stage`, `claims.startStage` and `claims.expiredStage` take a key or `{ category }`. Doctor reports BS245 for a missing stage.
- `hold.kinds` limits the kinds `hold` accepts, `hold.approval.kinds` limits the ones that open an approval, and releasing, leaving the hold stage or closing cancels the pending request. `task.hold_released` carries `approvalCancelled`.
- `delegate({ toProfile })` reserves a task for a profile (`delegate_task(..., to_profile)`, `TASK_RESERVED`). Tasks read back `delegateProfile`, `claimNext` takes `filter.delegateProfile`, and `task.delegated` carries `toProfile`. The old column value, the delegator label, is cleared.
- `before_task_close` runs once on every closing path from an after-update trigger, and a hook that raises refuses the close. It no longer runs on a reopen.
