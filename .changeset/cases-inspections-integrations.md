---
"better-supabase": minor
---

Connect `cases` and `inspections` to the other blocks. A tenant policy for subject `case` and action
`close` now blocks closing (`CASE_APPROVAL_REQUIRED`) until the request is approved, and closing a
case writes a version. Inspections take a `calendar` option that mirrors planned inspections as
all-day events, send `inspection.assigned` when someone joins the team, and report overdue
inspections through `notifyOverdue()` and a daily `overdue` schedule. See ADR 0148.
