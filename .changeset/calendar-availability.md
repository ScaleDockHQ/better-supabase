---
"better-supabase": minor
---

The calendar block can now tell you when members are free, and bookings can run appointment schedules.

- Events take a `kind` (`event`, `out_of_office` or `focus_time`), a `transparency` (`opaque` or `transparent`, mapped to the iCalendar `TRANSP` property) and `autoDecline`.
- `setWorkingHours` and `workingHours` store each member's weekly hours in a time zone, in the new `calendar_working_hours` table.
- `freeBusy(organizationId, userIds, range)` returns busy, out-of-office, focus-time and working-hours ranges per member. Postgres computes them, so recurring series, overrides, accepted invitations and approved leave all count. `commonFreeTime` finds the ranges when everyone is free.
- An out-of-office block, and a focus time block with `autoDecline`, declines new invitations it covers.
- Bookings resources take `hostUserId` and `checkBusy`, so their slots skip the times the host's calendar is busy. Use them for appointment schedules.

Run `better-supabase sql sync`, then generate a migration. The new columns have defaults, so existing rows keep working.
