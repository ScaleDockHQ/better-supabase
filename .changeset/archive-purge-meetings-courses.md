---
"better-supabase": minor
---

Breaking: meetings and courses can be archived and restored, and their hard
delete is `purge`, behind `permissions.purge` (ADR 1045). A held or cancelled
meeting is archived and an archived meeting takes no changes. A course archives
through its `archived` status and restores as a draft, so no column is added for
it.

| Before                     | After                  |
| -------------------------- | ---------------------- |
| `meetings.delete(id)`      | `meetings.purge(id)`   |
| `delete_meeting(id)` (SQL) | `purge_meeting(id)`    |
| event `meeting.deleted`    | event `meeting.purged` |
| `courses.delete(id)`       | `courses.purge(id)`    |
| `delete_course(id)` (SQL)  | `purge_course(id)`     |
| event `course.deleted`     | event `course.purged`  |

Run `better-supabase upgrade` and apply the migration, which adds
`archived_at` to meetings. See the 0.66 to 0.67 guide.
