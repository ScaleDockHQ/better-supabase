---
"better-supabase": minor
---

Breaking: a calendar event's hard delete is `purge`, behind `permissions.purge`,
which falls back to the former `delete` key (ADR 1081). A cancelled event keeps
its `status` as the archive, so events get no `archive`, `restore` or new
column. Removing one occurrence of a series still uses `permissions.delete`.

| Before                         | After                                     |
| ------------------------------ | ----------------------------------------- |
| `calendar.delete(eventId)`     | `calendar.purge(eventId)`                 |
| `delete_calendar_event(id)`    | `purge_calendar_event(event_id)` (SQL)    |
| event `calendar_event.deleted` | event `calendar_event.purged`             |
| `permissions.delete`           | `permissions.purge` (`delete` still read) |

Run `better-supabase upgrade` and apply the migration. See the 0.66 to 0.67
guide.
