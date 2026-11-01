---
"better-supabase": minor
---

`payroll-export` now counts only the time entries of weeks with an approved timesheet. A week that is open, submitted or rejected adds no line, and approving it adds its hours the next time the draft run is refreshed.

`time-tracking` gains the `time_week_approved` function. Run `better-supabase upgrade` and generate a migration; it replaces `collect_payroll_lines` and adds that function.
