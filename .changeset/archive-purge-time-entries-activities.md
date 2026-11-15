---
"better-supabase": minor
---

Breaking: time entries and activities can be archived and restored, and their
hard delete is `purge`, behind `permissions.purge` (ADRs 1046 and 1047). An
archived time entry leaves lists, timesheet totals, billing, costing, payroll
and metrics and never blocks an overlap. An archive, restore or purge in a
submitted or approved week fails with `TIME_PERIOD_LOCKED`, so an entry is
never restored into a locked period. An archived activity leaves the timeline,
next step, open list, search and recordings and takes no changes.

| Before                        | After                     |
| ----------------------------- | ------------------------- |
| `timeEntries.remove(id)`      | `timeEntries.purge(id)`   |
| `delete_time_entry(id)` (SQL) | `purge_time_entry(id)`    |
| event `time_entry.deleted`    | event `time_entry.purged` |
| `activities.remove(id)`       | `activities.purge(id)`    |
| `delete_activity(id)` (SQL)   | `purge_activity(id)`      |
| event `activity.deleted`      | event `activity.purged`   |

Run `better-supabase upgrade` and apply the migration, which adds `archived_at`
to time entries and activities. See the 0.66 to 0.67 guide.
