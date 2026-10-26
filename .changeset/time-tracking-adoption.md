---
"better-supabase": minor
---

`time-tracking`: `options.approvals: false` drops the approvals dependency; timesheets then keep a `status` column (open, submitted, approved, rejected) with optional `decidedBy`, `decidedAt` and `decisionNote`, and members with `time_tracking.approve` decide through `approve_timesheet` and the new `reject_timesheet` (client `approve` and `reject`, event `timesheet.rejected`). `options.userTimeZone` starts each member's week in the zone a column of yours holds, through a new `time_week(at, user_id)`. Over your own entries table, an entry can be a start and a duration (`endedAt: null`, `seconds` as the writable duration column, `runningSince` as the running mark). Without these settings the module renders as before.
