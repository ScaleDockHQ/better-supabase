---
"better-supabase": minor
---

New block `better-supabase/blocks/leave` (`better-supabase add leave`): leave types in days or hours, requests that go through the `approvals` module, and a balance ledger per member and year. A request books the working days in `blocks.leave.options.workingDays` (Monday to Friday by default) or a half day, can't overlap another pending or approved request, and can't exceed the available balance unless `allowNegative` is on. The final approval books it as taken leave, and cancelling approved leave gives the days back. `createLeave()` adds `accrue` (idempotent with a key, for a monthly cron), `adjust` and `closePeriod`, which carries each balance up to the type's `carryoverMax` into the next year and expires the rest. The `access` module adds `leave.request` (members), `leave.read`, `leave.approve` and `leave.manage` (admins); re-run `better-supabase sql sync` to pick up the new default permissions.
