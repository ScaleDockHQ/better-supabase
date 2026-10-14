---
"better-supabase": minor
---

Add the `time-tracking` SQL module and `better-supabase/blocks/time-tracking`: timers and logged time on any record, with one running timer per member and no overlapping entries enforced by an exclusion constraint. A member submits a week as a timesheet that goes through the approvals module; the week is locked while the request is pending and once it is approved, and `reopen` unlocks it. `toWeeklyGrid` turns a week's entries into rows per record and day for a weekly data grid.
